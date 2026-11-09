package com.shellx.core.demo

import com.shellx.core.link.MachineLinkConnecting
import com.shellx.link.account.PairedMachine
import com.shellx.link.core.AgentSession
import com.shellx.link.core.ChatAttachment
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.LinkSession
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.NoiseException
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.PairingOffer
import com.shellx.link.core.PendingItem
import com.shellx.link.core.ReplyOutcome
import com.shellx.link.core.ShellXLink
import com.shellx.link.core.TerminalGridFrame
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalViewEndReason
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.WorkspaceControlOutcome
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
 * still acts once released, even when the phone's session ended meanwhile. Attachment uploads are driven by the phone,
 * as 3B's client does: an upload whose call ended (session closed, caller cancelled) stops, and its message is never
 * typed.
 *
 * Calls never time out, unlike 3B's client (`LinkTimings.requestTimeout`): a held call waits until it is released or
 * the session ends, whatever virtual time passes. To test a `TimedOut` path, wrap the connector (or the session it
 * returns) and throw `LinkClientException.TimedOut()` from the wrapper.
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
    /** False: no `terminal_view` feature (a ShellX from before it). A Mac without workspaces never advertises it either. */
    val servesTerminalViews: Boolean = true,
    /** False: no `terminal_create` feature. A Mac without workspaces never advertises it either. */
    val acceptsTerminalCreate: Boolean = true,
    internal val nowMs: () -> Long = System::currentTimeMillis,
) {
    data class Decision(val requestId: String, val decision: LinkDecision)

    data class SentText(val sessionId: String, val text: String) {
        override fun toString(): String = "SentText(sessionId=$sessionId, text=<redacted>)"
    }

    data class HistoryRequest(val sessionId: String, val beforeSeq: Long?, val limit: Int)

    data class Interrupt(val sessionId: String, val hard: Boolean)

    data class TerminalCloseCall(val workspaceId: String, val terminalId: String)

    /** The grid of a terminal view open or resize, as the Mac took it (clamped). */
    data class TerminalViewSize(val terminalId: String, val cols: Int, val rows: Int)

    private val live = FakeMacLive()
    private val lock = live.lock
    private var hostKey = NoiseStaticKey.generate()
    private var connects = 0
    private var failure: Exception? = null
    private var failuresLeft = 0
    private val phoneCalls = AtomicInteger()

    internal val feed = FakeMacFeed(live)
    internal val sessionSource = FakeMacSessions(live, pushes = servesSessionsAndChat)
    internal val workspaceSource = FakeMacWorkspaces(live, pushes = servesWorkspaces, sessionSource, nowMs)
    internal val chat = FakeMacChat(live, pushes = servesSessionsAndChat)
    internal val terminals = FakeMacTerminals(live, workspaceSource, scope)

    /** The pairing record a phone keeps for this Mac: machineId "mac-<id>", linkSlot "slot-<id>", the first host key. */
    val machine: PairedMachine

    /** `welcome.features` of every session this Mac opens. */
    internal val hostFeatures: Set<String> = buildSet {
        if (servesSessionsAndChat && acceptsAttachments) add(ShellXLink.ATTACHMENTS_FEATURE)
        if (servesWorkspaces) add(ShellXLink.WORKSPACES_FEATURE)
        if (servesWorkspaces && acceptsWorkspaceControl) add(ShellXLink.WORKSPACE_CONTROL_FEATURE)
        if (servesSessionsAndChat && acceptsAgentClose) add(ShellXLink.AGENT_CLOSE_FEATURE)
        if (servesWorkspaces && acceptsTerminalClose) add(ShellXLink.TERMINAL_CLOSE_FEATURE)
        if (servesWorkspaces && servesTerminalViews) add(ShellXLink.TERMINAL_VIEW_FEATURE)
        if (servesWorkspaces && acceptsTerminalCreate) add(ShellXLink.TERMINAL_CREATE_FEATURE)
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
     * Every [LinkSession] call any phone made, over all sessions (close and the five Flows do not count, nor an input
     * that `TerminalInputCheck` refuses: nothing was sent). A test reads it before and after an action to show that
     * nothing at all was sent.
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

    /** Ends every live session from the Mac's side: each one's five Flows complete, its view closes, and its pending calls throw SessionClosed. */
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

    // Workspace, agent and terminal control (FakeMacWorkspaces)

    /** Every workspace control call the Mac received, in order: `create`, `rename:<id>:<title>`, `close:<id>`. */
    val workspaceCalls: List<String> get() = workspaceSource.controlCalls

    /**
     * The next workspace control call answers [outcome] and, unless it is `OK`, changes nothing. Without it the Mac acts
     * as the real one does: it makes the workspace, renames or closes one it has (`NOT_FOUND` otherwise) and keeps its
     * last workspace (`REFUSED`).
     */
    fun setNextWorkspaceOutcome(outcome: WorkspaceControlOutcome) = workspaceSource.setNextOutcome(outcome)

    /** From now on control calls (workspace, agent and terminal) are recorded but not answered until released. */
    fun holdWorkspaceControl() = workspaceSource.hold.hold()

    fun releaseWorkspaceControl() = workspaceSource.hold.release()

    /** The session id of every agent close the Mac received, in order. */
    val agentCloses: List<String> get() = workspaceSource.agentCloses

    /**
     * The next agent close answers [outcome] and, unless it is `OK`, changes nothing. Without it a session the Mac lists
     * that has not ended turns `ENDED` (`OK`); any other id is `NOT_FOUND`.
     */
    fun setNextAgentCloseOutcome(outcome: WorkspaceControlOutcome) = workspaceSource.setNextAgentCloseOutcome(outcome)

    /** Every terminal close the Mac received, in order. */
    val terminalCloses: List<TerminalCloseCall> get() = workspaceSource.terminalCloses

    /**
     * The next terminal close answers [outcome] and, unless it is `OK`, changes nothing. Without it a terminal that the
     * named workspace lists is closed (`OK`), and the workspace goes with its last terminal; any other pair is `NOT_FOUND`.
     */
    fun setNextTerminalCloseOutcome(outcome: WorkspaceControlOutcome) =
        workspaceSource.setNextTerminalCloseOutcome(outcome)

    // Terminal views and terminal creation (FakeMacTerminals)

    /** The content of each terminal by id; every other terminal shows `DemoTerminalScreens.prompt` at the size asked for. */
    fun setTerminalFixtures(fixtures: Map<String, DemoTerminalFixture>) = terminals.setFixtures(fixtures)

    /** From now on an open of [terminalId] answers [outcome] (OK counts as FAILED, as the Mac's view slot answers). */
    fun refuseTerminalView(terminalId: String, outcome: TerminalViewOpenOutcome) = terminals.refuse(terminalId, outcome)

    /** From now on terminal view opens are recorded in [terminalViewOpens] but not answered until released. */
    fun holdTerminalViewOpens() = terminals.hold.hold()

    fun releaseTerminalViewOpens() = terminals.hold.release()

    /** [frame] goes out as the next revision of every view of [terminalId] (the Mac's terminal printed something). */
    fun emitTerminalFrame(terminalId: String, frame: TerminalGridFrame) = terminals.emit(terminalId, frame)

    /** Every session viewing [terminalId] gets `terminal.view.ended` with [reason], and those views close. */
    fun endTerminalView(terminalId: String, reason: TerminalViewEndReason) = terminals.end(terminalId, reason)

    /** The next `terminal.create` answers [outcome] and, unless it is `OK`, adds nothing. */
    fun setNextTerminalCreateOutcome(outcome: WorkspaceControlOutcome) = terminals.setNextCreateOutcome(outcome)

    /** Every terminal view open the Mac took, in order, refused ones too (not one answered `busy`). */
    val terminalViewOpens: List<TerminalViewSize> get() = terminals.viewOpens

    /** Every resize of a viewed terminal, in order. */
    val terminalViewResizes: List<TerminalViewSize> get() = terminals.viewResizes

    /** The terminal id of every view that closed, in order: by the phone, a new open of it, its end or its session's. */
    val terminalViewCloses: List<String> get() = terminals.viewCloses

    /** Every input message applied to a view of [terminalId], in order. */
    fun terminalViewInputs(terminalId: String): List<List<TerminalInputUnit>> = terminals.viewInputs(terminalId)

    /** How many resyncs of a view of [terminalId] the Mac answered. */
    fun terminalViewSnapshotRequests(terminalId: String): Int = terminals.viewSnapshotRequests(terminalId)

    /** The workspace id of every `terminal.create` the Mac took, in order. */
    val terminalCreates: List<String> get() = terminals.createCalls

    // Chat (FakeMacChat)

    fun setHistory(sessionId: String, entries: List<ChatEntry>) = chat.setHistory(sessionId, entries)

    fun pushChat(sessionId: String, entries: List<ChatEntry>) = chat.push(sessionId, entries)

    /**
     * The Mac reloads the session's transcript (its `seq` values start over): the transcript becomes [entries] and phones
     * get `ChatPush.Reset`, in order with the session's pushes.
     */
    fun resetChat(sessionId: String, entries: List<ChatEntry>) = chat.reset(sessionId, entries)

    /** Null goes back to `SUBMITTED` for a known transcript and `NOT_FOUND` otherwise. */
    fun setSendOutcome(outcome: ChatSendOutcome?) = chat.setSendOutcome(outcome)

    val sentTexts: List<SentText> get() = chat.sentTexts

    /** The attachments of every message the Mac took, in order (their messages are in [sentTexts]). */
    val receivedAttachments: List<ChatAttachment> get() = chat.receivedAttachments

    /** Null goes back to `SENT` for a known transcript and `NOT_FOUND` otherwise. */
    fun setInterruptOutcome(outcome: ChatInterruptOutcome?) = chat.setInterruptOutcome(outcome)

    val interrupts: List<Interrupt> get() = chat.interrupts

    /** Every history request that reached the transcript, in order. */
    val historyRequests: List<HistoryRequest> get() = chat.historyRequests

    /** From now on chat calls (history, send, interrupt) are recorded but not answered until [releaseChat]. */
    fun holdChat() = chat.hold.hold()

    fun releaseChat() = chat.hold.release()
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
