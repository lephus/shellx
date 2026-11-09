package com.shellx.core.link

import com.shellx.core.account.AccountVault
import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.home.SessionFinishDetector
import com.shellx.core.pending.DecisionSending
import com.shellx.core.platform.Clock
import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.KeyValueStore
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.ChatHistoryPage
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.LinkSession
import com.shellx.link.core.ReplyOutcome
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.ComparableTimeMark
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Each Mac's session list whenever it changes ([MachineHub.sessionUpdates]). */
data class MachineSessions(val machineId: String, val sessions: List<AgentSession>)

/** Each Mac's link state whenever its connection reports one ([MachineHub.stateUpdates]). */
data class MachineStateUpdate(val machineId: String, val state: MachineLinkState)

/**
 * Every paired Mac and its Link for the signed-in account (MachineHub.swift): one [MachineConnection] per Mac, the
 * merged pending items and live sessions, and the calls that act on them. The hub is the only writer of the vault's
 * Mac list: [start] reads it, [add] and [unpair] write it.
 *
 * Main-confined. Its own work runs in [scope], a child of the scope it was given: [stopAll] cancels it, as its last
 * step. Every change of what it shows goes through [state].
 */
class MachineHub(
    private val vault: AccountVault,
    private val relay: RelayAccountCalling,
    private val connector: MachineLinkConnecting,
    internal val latency: LatencyLog,
    private val settings: KeyValueStore,
    scope: CoroutineScope,
    private val clock: Clock,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
    private val onUnauthorized: suspend () -> Unit,
) : DecisionSending {
    companion object {
        /** How long sessions stay open after the app went to the background. */
        val BACKGROUND_GRACE: Duration = 25.seconds
        const val DEFAULT_MACHINE_KEY = "shellx.defaultMachineID"

        /** How many items [leftWhileSynced] remembers; the oldest go first. */
        const val HANDLED_MEMORY = 256
    }

    sealed class AddException(message: String) : Exception(message) {
        /** No account is signed in (or the hub was stopped by a sign-out). */
        class NotSignedIn : AddException("not_signed_in")
    }

    /** The hub's own scope: models of this account run in it. */
    val scope: CoroutineScope = CoroutineScope(scope.coroutineContext + SupervisorJob(scope.coroutineContext[Job]))

    private val _state = MutableStateFlow(HubState(storedDefaultMachineId = settings.getString(DEFAULT_MACHINE_KEY)))
    val state: StateFlow<HubState> = _state.asStateFlow()

    val machines: List<MachineModel> get() = state.value.machines
    val isLoaded: Boolean get() = state.value.isLoaded
    val finishTimes: Map<String, Map<String, Long>> get() = state.value.finishTimes

    /**
     * The Mac new messages go to when nothing else picks one: the chosen one while it is paired, otherwise the first
     * Mac. Kept in [settings] under [DEFAULT_MACHINE_KEY]; null removes it.
     */
    var defaultMachineId: String?
        get() = state.value.defaultMachineId
        set(value) {
            _state.update { it.copy(storedDefaultMachineId = value) }
            settings.putString(DEFAULT_MACHINE_KEY, value)
        }

    val defaultMachineListedWorkspaces: Boolean get() = state.value.defaultMachineListedWorkspaces
    val pendingItems: List<MachinePendingItem> get() = state.value.pendingItems
    val liveSessions: List<MachineSession> get() = state.value.liveSessions
    val reachableSessions: List<MachineSession> get() = state.value.reachableSessions

    fun leftWhileSynced(key: PendingKey): Boolean = state.value.leftWhileSynced(key)

    /**
     * How many times the session's transcript was reset (`chat.reset`) since the hub started, counted as each reset
     * arrives, before any subscriber sees it. A screen that stopped following the chat compares it when it follows
     * again: a reset it missed voids its copy. Not observable.
     */
    fun transcriptResets(ref: SessionRef): Int = resetCounts[ref] ?: 0

    /** The vault's Mac list as last read or written. */
    private var records: List<PairedMachine> = emptyList()
    private val connections = HashMap<String, MachineConnection>()
    private val readers = HashMap<String, Job>()
    private val chatSubscribers = Subscribers<ChatUpdate>()
    private val sessionSubscribers = Subscribers<MachineSessions>()
    private val stateSubscribers = Subscribers<MachineStateUpdate>()
    private var started = false
    private var stopped = false
    private var unauthorizedReported = false

    /** The app is in the background (until [appDidBecomeActive]). */
    private var inBackground = false

    /** The sessions were closed because the app stayed in the background past the grace. */
    private var suspended = false
    private var grace: Deferred<Boolean>? = null

    /** When the app went to the background, by [Clock.monotonic] (which counts deep sleep on Android). */
    private var backgroundSince: ComparableTimeMark? = null

    /** Transcript resets per session since the hub started ([transcriptResets]). */
    private val resetCounts = HashMap<SessionRef, Int>()

    /** Tells which sessions finished a turn, from every session list a Mac sends ([finishTimes]). */
    private val finishDetector = SessionFinishDetector()

    internal val chatSubscriberCount: Int get() = chatSubscribers.count
    internal val connectionCount: Int get() = connections.size
    internal val sessionSubscriberCount: Int get() = sessionSubscribers.count

    // Lifecycle

    /** Reads the paired Macs from the vault and connects to each. Runs once. */
    suspend fun start() {
        if (started || stopped) return
        started = true
        try {
            records = vault.machines()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CoreLog.log("hub_machines_unreadable")
        }
        if (stopped) return
        val added = records.filter { record -> state.value.machine(record.machineId) == null }.map { MachineModel(it) }
        _state.update { it.copy(machines = it.machines + added, isLoaded = true) }
        for (model in added) connect(model.id)
    }

    /** Stops every connection and completes the update flows. The hub is done afterwards: its [scope] is cancelled. */
    suspend fun stopAll() {
        stopped = true
        grace?.cancel()
        grace = null
        for (reader in readers.values) reader.cancel()
        readers.clear()
        val all = connections.values.toList()
        connections.clear()
        for (connection in all) connection.stop()
        chatSubscribers.closeAll()
        sessionSubscribers.closeAll()
        stateSubscribers.closeAll()
        _state.update { it.copy(machines = it.machines.map { model -> model.copy(pendingActionable = false) }) }
        scope.cancel()
    }

    /**
     * Saves a newly paired Mac (owned by the signed-in account) and connects to it. A Mac already paired under the same
     * machineId is replaced. Throws [AddException.NotSignedIn] when no account is signed in or the hub was stopped.
     */
    suspend fun add(machine: PairedMachine) {
        if (!started) start()
        if (stopped) throw AddException.NotSignedIn()
        val owner = vault.session()?.userId ?: throw AddException.NotSignedIn()
        // The list changes before the write, so overlapping adds each write every Mac.
        val old = records.firstOrNull { it.machineId == machine.machineId }
        records = upsert(machine, records)
        try {
            vault.setMachines(records, owner)
        } catch (e: Exception) {
            records = if (old != null) upsert(old, records) else records.filter { it.machineId != machine.machineId }
            throw e
        }
        if (stopped) return
        if (state.value.machine(machine.machineId) != null) {
            disconnect(machine.machineId)
            // A sign-out may have stopped the hub while the old connection closed.
            if (stopped) return
            _state.update { s ->
                s.copy(machines = s.machines.map { if (it.id == machine.machineId) MachineModel(machine) else it })
            }
            forgetFinishes(machine.machineId)
        } else {
            _state.update { it.copy(machines = it.machines + MachineModel(machine)) }
        }
        connect(machine.machineId)
    }

    /**
     * Removes this phone from a Mac: finds the Mac's grant with `machines(token)`, deletes it on the relay, then forgets
     * the Mac (vault, connection, list, default).
     *
     * A grant that is already gone (not listed, or 404) still forgets the Mac. Any other relay error (network, 5xx)
     * throws and keeps the Mac as it was; a 401 also signs out. A Revoked Mac has no grant left, so it is forgotten even
     * when the relay cannot be reached. An unknown machineId does nothing.
     */
    suspend fun unpair(machineId: String) {
        if (state.value.machine(machineId) == null) return
        if (stopped) throw AddException.NotSignedIn()
        val session = vault.session() ?: throw AddException.NotSignedIn()
        try {
            removeGrant(machineId, session.token)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (LinkFailure.of(e) == LinkFailure.SIGNED_OUT) {
                reportUnauthorized()
                throw e
            }
            // The Mac already let this phone go: nothing is left on the relay to remove.
            if (state.value.machine(machineId)?.state != MachineLinkState.Revoked) throw e
            CoreLog.log("unpair_revoked_relay_unreachable")
        }
        // A sign-out meanwhile wipes the vault: writing the list now would bring it back.
        if (stopped) throw AddException.NotSignedIn()
        forget(machineId, session.userId)
    }

    /**
     * Asks the relay which Macs this phone may still reach: a Mac missing from the list becomes Revoked (its connection
     * stops), and a renamed Mac takes its new name. A 401 signs out.
     */
    suspend fun refreshGrants() {
        if (stopped) return
        val token = try {
            vault.session()?.token ?: return
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return
        }
        // What each Mac was paired as when the request left: a Mac re-paired meanwhile (replaced by `add`) or added
        // meanwhile may not be in this list yet.
        val known = state.value.machines.map { it.id to it.machine }
        val grants = try {
            relay.machines(token)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (LinkFailure.of(e) == LinkFailure.SIGNED_OUT) reportUnauthorized()
            return
        }
        if (stopped) return
        val byId = LinkedHashMap<String, PairedMachineListing>()
        for (grant in grants) if (grant.machineId !in byId) byId[grant.machineId] = grant
        for ((id, machine) in known) {
            // The hub still has this Mac, with the pairing record it had when the request left.
            val current = state.value.machine(id) ?: continue
            if (current.machine != machine) continue
            if (stopped) return
            val grant = byId[id]
            if (grant != null) {
                if (current.name != grant.name) updateModel(id) { it.copy(name = grant.name) }
            } else if (current.state != MachineLinkState.Revoked) {
                revoke(id)
            }
        }
    }

    /**
     * Android: ProcessLifecycleOwner ON_START (3D). Cancels the grace. When the sessions were closed, reconnects every
     * Mac; otherwise asks each Mac that is not online to retry now.
     *
     * Android additions:
     * - When the app went to the background [BACKGROUND_GRACE] or more ago by [Clock.monotonic] but the grace never ran
     *   out (a frozen or dozing process), it first detaches every connection, as the grace would have, so every Mac
     *   reconnects from scratch (ledger A-7).
     * - On a return within the grace, each online Mac's session is probed (3B M-3): the Link client's liveness timers
     *   do not count deep sleep, so a session that died while the phone slept could otherwise look alive for most of a
     *   minute. One that does not answer is replaced at once.
     */
    fun appDidBecomeActive() {
        val since = backgroundSince
        backgroundSince = null
        inBackground = false
        grace?.cancel()
        grace = null
        if (stopped) return
        if (!suspended && since != null && since.elapsedNow() >= BACKGROUND_GRACE) {
            CoreLog.log("hub_frozen_return")
            val closing = detachAll()
            scope.launch { for (connection in closing) connection.stop() }
        }
        if (suspended) {
            resume()
            return
        }
        for (model in state.value.machines) {
            val connection = connections[model.id] ?: continue
            if (model.state != MachineLinkState.Online) {
                // Coming back is a good moment to retry a Mac that was out of reach.
                connection.reconnectNow()
            } else if (since != null) {
                scope.launch { connection.checkAlive() }
            }
        }
    }

    /**
     * Android: ON_STOP (3D launches it in the app scope). Waits [BACKGROUND_GRACE] with `sleep`; when the app is still
     * in the background then, closes every session. Returns early when the app comes back. Records
     * `clock.monotonic.markNow()` for [appDidBecomeActive]'s frozen-return rule.
     */
    suspend fun appDidEnterBackground() {
        if (stopped || suspended) return
        inBackground = true
        backgroundSince = clock.monotonic.markNow()
        grace?.cancel()
        val wait = scope.async {
            try {
                sleep(BACKGROUND_GRACE)
                true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                false
            }
        }
        grace = wait
        val elapsed = try {
            wait.await()
        } catch (e: CancellationException) {
            // The grace was cancelled (the app came back, or the hub stopped); the caller's own cancellation propagates.
            currentCoroutineContext().ensureActive()
            false
        }
        if (!elapsed || !inBackground || grace !== wait || stopped) return
        grace = null
        suspend()
    }

    /**
     * Closes every session at once (iOS: background time expired). Everything that matters happens before this returns
     * (items not actionable, connections detached), so a return reconnects every Mac from scratch even if the process
     * is frozen before the sessions finish closing. Android keeps it for a future signal; today only tests call it.
     */
    fun backgroundTimeExpired() {
        if (stopped || suspended) return
        inBackground = true
        grace?.cancel()
        grace = null
        val closing = detachAll()
        scope.launch { for (connection in closing) connection.stop() }
    }

    /**
     * The default network changed (NetworkChangeFilter's onChange, 3D): a session, or an attempt still syncing, may ride
     * a dead path without anyone knowing yet, so each connection replaces its client at once, and one without a client
     * retries now. The connection decides from its own state; the model's copy may lag.
     */
    fun networkChanged() {
        if (stopped || suspended) return
        for (connection in connections.values.toList()) scope.launch { connection.forceReconnect() }
    }

    // Calls

    /** Sends one `agent.reply`. DecisionCenter calls it for a tap (and records REPLY_ROUND_TRIP from the tap). */
    override suspend fun reply(key: PendingKey, decision: LinkDecision): ReplyOutcome =
        withLink(key.machineId) { it.reply(key.requestId, decision) }

    suspend fun chatHistory(ref: SessionRef, beforeSeq: Long?, limit: Int): ChatHistoryPage =
        withLink(ref.machineId) { it.chatHistory(ref.sessionId, beforeSeq, limit) }

    suspend fun chatSend(ref: SessionRef, text: String): ChatSendOutcome =
        withLink(ref.machineId) { it.chatSend(ref.sessionId, text) }

    suspend fun chatInterrupt(ref: SessionRef, hard: Boolean): ChatInterruptOutcome =
        withLink(ref.machineId) { it.chatInterrupt(ref.sessionId, hard) }

    /**
     * Chat pushes from every Mac as they arrive, in order: entries, and transcript resets. Each call registers a
     * subscriber at once; a collector that ends unregisters it, and so does a closed channel found at the next publish.
     * Nothing is replayed.
     */
    fun chatUpdates(): Flow<ChatUpdate> = chatSubscribers.subscribe()

    /** Each Mac's session list whenever it changes. Multicast like [chatUpdates]. */
    fun sessionUpdates(): Flow<MachineSessions> = sessionSubscribers.subscribe()

    /** Each Mac's link state whenever its connection reports one (Online once a new session is synced). Multicast. */
    fun stateUpdates(): Flow<MachineStateUpdate> = stateSubscribers.subscribe()

    // Connections

    private fun connect(machineId: String) {
        // A stopped hub (signed out, or 401) never starts a connection: nobody reads its events.
        if (stopped) return
        val model = state.value.machine(machineId) ?: return
        connections[machineId]?.let { old ->
            readers.remove(machineId)?.cancel()
            scope.launch { old.stop() }
        }
        val connection = MachineConnection(model.machine, connector, latency, scope, clock, sleep = sleep)
        connections[machineId] = connection
        readers[machineId] = scope.launch { connection.events.collect { apply(it, connection, machineId) } }
        connection.start()
    }

    private suspend fun disconnect(machineId: String) {
        readers.remove(machineId)?.cancel()
        connections.remove(machineId)?.stop()
    }

    private fun apply(event: MachineEvent, connection: MachineConnection, machineId: String) {
        // A connection that was replaced or stopped no longer speaks for the Mac.
        if (connections[machineId] !== connection) return
        val model = state.value.machine(machineId) ?: return
        when (event) {
            is MachineEvent.Features ->
                if (model.hostFeatures != event.features) updateModel(machineId) { it.copy(hostFeatures = event.features) }
            is MachineEvent.State -> {
                updateModel(machineId) { it.copy(state = event.state) }
                stateSubscribers.publish(MachineStateUpdate(machineId, event.state))
            }
            is MachineEvent.Pending -> _state.update { s ->
                val before = s.machine(machineId)?.pending ?: PendingSet()
                val handled = if (event.actionable) rememberHandled(s.handled, before, event.set, machineId) else s.handled
                s.copy(
                    machines = s.machines.map {
                        if (it.id == machineId) it.copy(pending = event.set, pendingActionable = event.actionable) else it
                    },
                    handled = handled,
                )
            }
            is MachineEvent.Sessions -> {
                val finishTimes = noteFinishes(state.value.finishTimes, event.set.sessions, machineId)
                _state.update { s ->
                    s.copy(
                        machines = s.machines.map {
                            if (it.id == machineId) it.copy(sessions = event.set, sessionsSupported = event.supported) else it
                        },
                        finishTimes = finishTimes,
                    )
                }
                sessionSubscribers.publish(MachineSessions(machineId, event.set.sessions))
            }
            is MachineEvent.Workspaces ->
                updateModel(machineId) { it.copy(workspaces = event.set, workspacesSupported = event.supported) }
            is MachineEvent.Chat -> publishChat(event.sessionId, model) { ChatUpdate.Upsert(it, event.entries) }
            is MachineEvent.ChatReset -> {
                val ref = SessionRef(machineId, event.sessionId, "", "")
                resetCounts[ref] = (resetCounts[ref] ?: 0) + 1
                publishChat(event.sessionId, model) { ChatUpdate.Reset(it) }
            }
            MachineEvent.SignedOut -> scope.launch { reportUnauthorized() }
        }
    }

    /**
     * Takes the Mac's session list into the finish detector: the sessions it reports finished are [finishTimes] until
     * they work again (or leave the list, or the user marks them seen). Returns [times] with the Mac's finishes updated.
     */
    private fun noteFinishes(
        times: Map<String, Map<String, Long>>,
        sessions: List<AgentSession>,
        machineId: String,
    ): Map<String, Map<String, Long>> {
        val finished = finishDetector.observe(machineId, sessions)
        val idle = sessions.filter { it.state == AgentState.IDLE }.map { it.sessionId }.toSet()
        val before = times[machineId].orEmpty()
        // A session already finished keeps its first time; a new finish gets the phone's clock now.
        val kept = before.filterKeys { it in idle }.toMutableMap()
        val seenAt = clock.nowMs()
        for (ref in finished) if (ref.sessionId !in kept) kept[ref.sessionId] = seenAt
        return when {
            kept == before -> times
            kept.isEmpty() -> times - machineId
            else -> times + (machineId to kept.toMap())
        }
    }

    /** Forgets what the finish detector knew of the Mac: its link is new, or gone. */
    private fun forgetFinishes(machineId: String) {
        finishDetector.retain(state.value.machines.map { it.id }.toSet() - machineId)
        _state.update { it.copy(finishTimes = it.finishTimes - machineId) }
    }

    /** [handled] with the items that leave [old] for [new], a list backed by a live, synced session. */
    private fun rememberHandled(handled: List<PendingKey>, old: PendingSet, new: PendingSet, machineId: String): List<PendingKey> {
        val kept = new.items.map { it.requestId }.toSet()
        val left = old.items.filter { it.requestId !in kept }
        if (left.isEmpty()) return handled
        return (handled + left.map { PendingKey(machineId, it.requestId) }).takeLast(HANDLED_MEMORY)
    }

    /** Hands a chat push to every subscriber, with the session's labels as the Mac lists it. */
    private fun publishChat(sessionId: String, model: MachineModel, update: (SessionRef) -> ChatUpdate) {
        if (chatSubscribers.count == 0) return
        val session = model.sessions.session(sessionId)
        val ref = SessionRef(model.id, sessionId, session?.agent ?: "", session?.workspaceTitle ?: "")
        chatSubscribers.publish(update(ref))
    }

    /** Deletes the relay's grant for [machineId], if it still has one. */
    private suspend fun removeGrant(machineId: String, token: String) {
        val grant = relay.machines(token).firstOrNull { it.machineId == machineId } ?: return
        try {
            relay.unpair(grant.grantId, token)
        } catch (e: RelayApiException.Http) {
            // Removed meanwhile (on the Mac, or by another unpair).
            if (e.status != 404) throw e
        }
    }

    /** Takes the Mac out of the vault, then out of the hub. A failed vault write keeps everything. */
    private suspend fun forget(machineId: String, owner: String) {
        val old = records.firstOrNull { it.machineId == machineId }
        records = records.filter { it.machineId != machineId }
        try {
            vault.setMachines(records, owner)
        } catch (e: Exception) {
            if (old != null) records = upsert(old, records)
            throw e
        }
        // Re-pairing the same Mac later should not make it the default again by surprise.
        if (state.value.storedDefaultMachineId == machineId) defaultMachineId = null
        if (state.value.machine(machineId) == null) return
        _state.update { s -> s.copy(machines = s.machines.filter { it.id != machineId }) }
        forgetFinishes(machineId)
        disconnect(machineId)
    }

    private suspend fun revoke(machineId: String) {
        disconnect(machineId)
        updateModel(machineId) {
            it.copy(
                state = MachineLinkState.Revoked, pending = PendingSet(), pendingActionable = false,
                sessions = SessionSet(), workspaces = WorkspaceSet(),
            )
        }
        forgetFinishes(machineId)
    }

    private suspend fun suspend() {
        for (connection in detachAll()) connection.stop()
    }

    /**
     * Marks every Mac as not live and takes every connection out of the hub, without waiting, so nothing can interleave
     * halfway. Returns the connections for the caller to stop.
     */
    private fun detachAll(): List<MachineConnection> {
        suspended = true
        _state.update { s ->
            s.copy(
                machines = s.machines.map { model ->
                    when {
                        model.state.isTerminal -> model
                        model.state == MachineLinkState.Online ->
                            model.copy(pendingActionable = false, state = MachineLinkState.Reconnecting)
                        else -> model.copy(pendingActionable = false)
                    }
                },
            )
        }
        for (reader in readers.values) reader.cancel()
        readers.clear()
        val detached = connections.values.toList()
        connections.clear()
        return detached
    }

    private fun resume() {
        if (stopped) return
        suspended = false
        for (model in state.value.machines) {
            if (!model.state.isTerminal && connections[model.id] == null) connect(model.id)
        }
    }

    /**
     * Runs [body] on the Mac's live session. Throws LinkCallException: UnknownMachine for a Mac not paired, NeedsPairing
     * for one that removed this phone or whose key changed, Offline (with the Mac's current name) when it has no live,
     * synced session. Errors of [body] itself (LinkClientException) pass through.
     */
    internal suspend fun <T> withLink(machineId: String, body: suspend (LinkSession) -> T): T {
        val model = state.value.machine(machineId) ?: throw LinkCallException.UnknownMachine()
        // It will not come back by itself, so it is not called offline.
        if (model.state.needsPairing) throw LinkCallException.NeedsPairing(model.name)
        val connection = connections[machineId] ?: throw LinkCallException.Offline(model.name)
        return try {
            connection.call(body)
        } catch (e: LinkCallException.Offline) {
            throw LinkCallException.Offline(model.name)
        }
    }

    /**
     * The relay refused the account token (401): tells the app once, which signs out to the "session expired" sign-in.
     * Also used by PairingModel for a 401 while pairing. After a stop (a sign-out), a late 401 answers a request made
     * with the dropped token, so it is not reported.
     */
    internal suspend fun reportUnauthorized() {
        if (unauthorizedReported || stopped) return
        unauthorizedReported = true
        onUnauthorized()
    }

    private fun updateModel(machineId: String, change: (MachineModel) -> MachineModel) {
        _state.update { s -> s.copy(machines = s.machines.map { if (it.id == machineId) change(it) else it }) }
    }

    private fun upsert(machine: PairedMachine, list: List<PairedMachine>): List<PairedMachine> =
        if (list.any { it.machineId == machine.machineId }) {
            list.map { if (it.machineId == machine.machineId) machine else it }
        } else {
            list + machine
        }
}

/**
 * The readers of one of the hub's update flows. Each [subscribe] registers a Channel(UNLIMITED) at once; a collector
 * that ends unregisters it, and a closed channel found at a [publish] is dropped. Thread-safe: a collector may end on
 * any thread.
 */
private class Subscribers<T> {
    private val channels = ArrayList<Channel<T>>()

    val count: Int get() = synchronized(channels) { channels.size }

    fun subscribe(): Flow<T> {
        val channel = Channel<T>(Channel.UNLIMITED)
        synchronized(channels) { channels += channel }
        return channel.consumeAsFlow().onCompletion { synchronized(channels) { channels -= channel } }
    }

    fun publish(value: T) {
        val all = synchronized(channels) { channels.toList() }
        val closed = all.filter { it.trySend(value).isClosed }
        if (closed.isNotEmpty()) synchronized(channels) { channels.removeAll(closed.toSet()) }
    }

    fun closeAll() {
        val all = synchronized(channels) { channels.toList().also { channels.clear() } }
        for (channel in all) channel.close()
    }
}
