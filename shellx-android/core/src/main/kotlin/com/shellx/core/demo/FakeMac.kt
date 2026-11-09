package com.shellx.core.demo

import com.shellx.core.link.MachineLinkConnecting
import com.shellx.link.account.PairedMachine
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.LinkSession
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.AgentSession
import com.shellx.link.core.NoiseException
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.PairingOffer
import com.shellx.link.core.PendingItem
import com.shellx.link.core.ReplyOutcome
import com.shellx.link.core.ShellXLink
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope

/**
 * A Mac running ShellX, in process (FakeMac.swift): the demo's Mac and the tests' Mac. It implements 3B's
 * [LinkSession] directly, with no codec and no Noise, and keeps the host rules a phone can observe (LinkHost.swift):
 * revisions, `unsupported` without a feature, the answers to every call.
 *
 * Every connect opens a new session with the Mac's current key and features, so [rotateHostKey] and
 * [failNextConnects] take effect on the next attempt. The Mac's side of each call runs in [scope], so a held call
 * still acts once released, even when the phone's session ended meanwhile.
 *
 * Thread-safe: one lock guards every part of the Mac, and it is never held across a suspension.
 */
class FakeMac(
    name: String,
    internal val scope: CoroutineScope,
    id: String? = null,
    /** False: no session list and no chat, like a ShellX from before agent sessions. */
    val servesSessionsAndChat: Boolean = true,
    /** False: the chat takes no attachments (no `attachments` feature). */
    val acceptsAttachments: Boolean = true,
    /** False: no workspace list and no workspace control (no `workspaces` or `workspace_control` feature). */
    val servesWorkspaces: Boolean = true,
    /** False: the Mac lists workspaces but takes no control of them (no `workspace_control` feature). */
    val acceptsWorkspaceControl: Boolean = true,
    /** False: no `agent_close` feature. A Mac without sessions never advertises it either. */
    val acceptsAgentClose: Boolean = true,
    /** False: no `terminal_close` feature. A Mac without workspaces never advertises it either. */
    val acceptsTerminalClose: Boolean = true,
    internal val nowMs: () -> Long = System::currentTimeMillis,
) {
    data class Decision(val requestId: String, val decision: LinkDecision)

    data class SentText(val sessionId: String, val text: String) {
        override fun toString(): String = "SentText(sessionId=$sessionId, text=<redacted>)"
    }

    data class HistoryRequest(val sessionId: String, val beforeSeq: Long?, val limit: Int)

    data class Interrupt(val sessionId: String, val hard: Boolean)

    data class TerminalCloseCall(val workspaceId: String, val terminalId: String)

    private val live = FakeMacLive()
    private val lock = live.lock
    private var hostKey = NoiseStaticKey.generate()
    private var connects = 0
    private var failure: Exception? = null
    private var failuresLeft = 0
    private val phoneCalls = AtomicInteger()

    internal val feed = FakeMacFeed(live)
    internal val sessionSource = FakeMacSessions(live, pushes = servesSessionsAndChat)
    internal val workspaceSource = FakeMacWorkspaces(live, pushes = servesWorkspaces)

    /** The pairing record a phone keeps for this Mac: machineId "mac-<id>", linkSlot "slot-<id>", the first host key. */
    val machine: PairedMachine

    /** `welcome.features` of every session this Mac opens. */
    internal val hostFeatures: Set<String> = buildSet {
        if (servesSessionsAndChat && acceptsAttachments) add(ShellXLink.ATTACHMENTS_FEATURE)
        if (servesWorkspaces) add(ShellXLink.WORKSPACES_FEATURE)
        if (servesWorkspaces && acceptsWorkspaceControl) add(ShellXLink.WORKSPACE_CONTROL_FEATURE)
        if (servesSessionsAndChat && acceptsAgentClose) add(ShellXLink.AGENT_CLOSE_FEATURE)
        if (servesWorkspaces && acceptsTerminalClose) add(ShellXLink.TERMINAL_CLOSE_FEATURE)
    }

    init {
        val slot = id ?: UUID.randomUUID().toString().lowercase()
        machine = PairedMachine("mac-$slot", name, "slot-$slot", hostKey.publicKey)
    }

    /** How many times a phone tried to connect, failed attempts included. */
    val connectCount: Int get() = synchronized(lock) { connects }

    /** How many sessions are being served right now. */
    val liveSessionCount: Int get() = live.count

    /**
     * Every [LinkSession] call any phone made, over all sessions (close and the four Flows do not count). A test reads
     * it before and after an action to show that nothing at all was sent.
     */
    val phoneCallCount: Int get() = phoneCalls.get()

    /** A connector to this Mac for a phone whose Link key [phoneKey] returns. The Mac trusts that key, as after pairing. */
    fun connector(phoneKey: suspend () -> NoiseStaticKey): MachineLinkConnecting = MachineLinkConnecting { machine ->
        phoneKey()
        open(machine)
    }

    // Connections

    /** The next [count] connects throw [error] (before any handshake), as the relay or the network would. */
    fun failNextConnects(error: Exception, count: Int) {
        synchronized(lock) {
            failure = error
            failuresLeft = count
        }
    }

    /** The Mac gets a new key: phones that pinned the old one refuse the handshake. */
    fun rotateHostKey() {
        synchronized(lock) { hostKey = NoiseStaticKey.generate() }
    }

    /** Ends every live session from the Mac's side: each one's four Flows complete and its pending calls throw SessionClosed. */
    fun dropLiveSessions() {
        for (session in live.takeAll()) session.end()
    }

    /** The QR code the Mac would show now: its current host key and a new one-time code. */
    fun pairingOffer(): PairingOffer {
        val key = synchronized(lock) { hostKey.publicKey }
        return PairingOffer.make(machine.machineId, machine.linkSlot, key, machine.name)
    }

    /** `pairingOffer().uri`: what scanning the Mac's QR code (or copying its code) gives. */
    fun pairingCode(): String = pairingOffer().uri

    private fun open(machine: PairedMachine): LinkSession = synchronized(lock) {
        connects += 1
        val error = failure
        if (failuresLeft > 0 && error != null) {
            failuresLeft -= 1
            throw error
        }
        if (!machine.hostKey.contentEquals(hostKey.publicKey)) throw NoiseException.UntrustedPeer()
        FakeMacSession(this, hostFeatures).also(live::addLocked)
    }

    internal fun notePhoneCall() {
        phoneCalls.incrementAndGet()
    }

    internal fun ended(session: FakeMacSession) {
        live.remove(session)
    }

    // Pending (FakeMacFeed)

    fun addPending(item: PendingItem) = feed.add(item)

    fun resolvePending(requestId: String) = feed.resolve(requestId)

    /** The next pending change arrives one revision too far, so the phone sees a gap. */
    fun skipNextPendingRevision() = feed.skipRevision()

    /**
     * Every reply waits [delay], then answers [outcome]; null goes back to answering from the pending set. A preset
     * `DELIVERED` also resolves the item, unless [resolves] is false: then the change waits for [resolvePending].
     */
    fun setReplyOutcome(outcome: ReplyOutcome?, delay: Duration = Duration.ZERO, resolves: Boolean = true) =
        feed.setReplyOutcome(outcome, delay, resolves)

    val decisions: List<Decision> get() = feed.decisions

    /** How many snapshots the Mac answered. */
    val snapshotCount: Int get() = feed.snapshotCount

    /** From now on a snapshot is not answered (the phone stays connected but unsynced) until [releaseSnapshots]. */
    fun holdSnapshots() = feed.snapshotHold.hold()

    fun releaseSnapshots() = feed.snapshotHold.release()

    /** How many snapshot requests are being held. */
    val heldSnapshotCount: Int get() = feed.snapshotHold.count

    // Sessions (FakeMacSessions)

    fun upsertSession(session: AgentSession) = sessionSource.upsert(session)

    fun removeSession(sessionId: String) = sessionSource.remove(sessionId)

    /** The next session change arrives one revision too far, so the phone sees a gap. */
    fun skipNextSessionRevision() = sessionSource.skipRevision()

    /** How many session lists the Mac answered. */
    val sessionListCount: Int get() = sessionSource.listCount

    // Workspace list (FakeMacWorkspaces)

    /** The Mac's workspaces become [workspaces]; phones get what differs as one change. */
    fun setWorkspaces(workspaces: List<LinkWorkspace>) = workspaceSource.set(workspaces)

    fun upsertWorkspace(workspace: LinkWorkspace) = workspaceSource.upsert(workspace)

    fun removeWorkspace(workspaceId: String) = workspaceSource.remove(workspaceId)

    /** The next workspace change arrives one revision too far, so the phone sees a gap. */
    fun skipNextWorkspaceRevision() = workspaceSource.skipRevision()

    /** How many workspace lists the Mac was asked for (a `too_large` answer counts). */
    val workspaceListCount: Int get() = workspaceSource.listCount
}

/** The live sessions of one [FakeMac], and the lock that guards every part of that Mac. */
internal class FakeMacLive {
    val lock = Any()
    private val sessions = LinkedHashSet<FakeMacSession>()

    val count: Int get() = synchronized(lock) { sessions.size }

    /** The caller holds [lock]. */
    fun addLocked(session: FakeMacSession) {
        sessions += session
    }

    fun remove(session: FakeMacSession) {
        synchronized(lock) { sessions -= session }
    }

    fun takeAll(): List<FakeMacSession> = synchronized(lock) { sessions.toList().also { sessions.clear() } }

    /** Hands [push] every live session. The caller holds [lock], so pushes keep the order of the Mac's changes. */
    fun broadcastLocked(push: (FakeMacSession) -> Unit) {
        for (session in sessions) push(session)
    }
}

/** Calls that wait while the Mac holds them (a slow Mac): `hold()`, then `release()` lets every one through. */
internal class FakeMacHold(private val lock: Any) {
    private var holding = false
    private val held = ArrayList<CompletableDeferred<Unit>>()

    /** How many calls are held right now. */
    val count: Int get() = synchronized(lock) { held.size }

    fun hold() {
        synchronized(lock) { holding = true }
    }

    fun release() {
        val waiting = synchronized(lock) {
            holding = false
            held.toList().also { held.clear() }
        }
        for (gate in waiting) gate.complete(Unit)
    }

    /** Returns at once unless the Mac holds calls; then waits for [release]. */
    suspend fun pass() {
        val gate = synchronized(lock) { if (holding) CompletableDeferred<Unit>().also(held::add) else null } ?: return
        try {
            gate.await()
        } catch (e: CancellationException) {
            synchronized(lock) { held.remove(gate) }
            throw e
        }
    }
}
