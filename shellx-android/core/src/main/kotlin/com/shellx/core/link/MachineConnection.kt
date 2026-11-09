package com.shellx.core.link

import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.platform.Clock
import com.shellx.core.platform.CoreLog
import com.shellx.link.account.PairedMachine
import com.shellx.link.core.AgentSession
import com.shellx.link.core.ChatPush
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkSession
import com.shellx.link.core.PendingChange
import com.shellx.link.core.SessionChange
import com.shellx.link.core.SessionList
import com.shellx.link.core.ShellXLink
import com.shellx.link.core.WorkspaceChange
import com.shellx.link.core.WorkspaceList
import kotlin.coroutines.cancellation.CancellationException
import kotlin.random.Random
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The Link to one paired Mac: one live session at a time, kept in sync, and brought back when it drops
 * (MachineConnection.swift). Main-confined: every member is called from the dispatcher of [scope], where the loop runs.
 *
 * One round: connect, `snapshot()`, `sessions()` (a Mac without a session list answers `unsupported`, which is not a
 * failure), `workspaces()` (only when the Mac lists the `workspaces` feature), report the session's `hostFeatures` and
 * Online, then read `changes`, `sessionChanges`, `workspaceChanges` and `chatEntries` until `changes` ends. A revision
 * gap resyncs inside the live session. When the session ends the items stay but are reported not actionable
 * (Reconnecting); when the first attempt after that fails they are dropped (Offline). Waits follow [schedule]; the
 * failure count starts over at every connect. A refused token ([MachineEvent.SignedOut]), a revoked grant, a changed
 * host key and a protocol mismatch stop the loop for good and complete [events].
 */
class MachineConnection(
    private val machine: PairedMachine,
    private val connector: MachineLinkConnecting,
    private val latency: LatencyLog,
    private val scope: CoroutineScope,
    private val clock: Clock,
    private val schedule: ReconnectSchedule = ReconnectSchedule.STANDARD,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
) {
    private val output = Channel<MachineEvent>(Channel.UNLIMITED)

    /** Every event in order. Single consumer: a Channel(UNLIMITED) as a Flow; it completes when the loop stops. */
    val events: Flow<MachineEvent> = output.consumeAsFlow()

    private var state: MachineLinkState = MachineLinkState.Connecting
    private var pending = PendingSet()
    private var sessions = SessionSet()
    private var sessionsSupported = true
    private var workspaces = WorkspaceSet()
    private var workspacesSupported = false

    /** The session of the current round, from connect until the round is over. */
    private var client: LinkSession? = null
    private var loop: Job? = null
    private var backoffWait: Job? = null

    /** Set by [reconnectNow] / [forceReconnect] when no wait is running: the next wait is skipped. */
    private var skipBackoff = false

    /** Set by [forceReconnect] when it closes the session: the round's end is ours, not a failure. */
    private var forcedClose = false

    /** Failures in a row since the last connect; a session that ended counts as one. */
    private var failures = 0

    /** When the last live session ended (epoch ms): what `Offline.sinceMs` reports. */
    private var lostAtMs: Long? = null

    /** True once [stop] ran or the loop stopped for good. */
    private var ended = false

    /** Starts the loop. Calling it again, or after [stop], does nothing. */
    fun start() {
        if (loop != null || ended) return
        emit(MachineEvent.State(MachineLinkState.Connecting))
        loop = scope.launch { run() }
    }

    /** Stops the loop, closes the live session and completes [events]. */
    suspend fun stop() {
        ended = true
        loop?.cancel()
        backoffWait?.cancel()
        client?.close()
        loop?.join()
        output.close()
    }

    /** Skips the rest of the current wait (or the next one, when an attempt is under way). */
    fun reconnectNow() {
        if (ended || state == MachineLinkState.Online) return
        val wait = backoffWait
        if (wait != null) wait.cancel() else skipBackoff = true
    }

    /**
     * Closes the current session and connects again at once: after a network change the session (or the attempt still
     * syncing) may ride a dead path without either side knowing yet. Dropping it is not a failure: no backoff, and the
     * items are not cleared. Without a session it is [reconnectNow].
     */
    suspend fun forceReconnect() {
        if (ended) return
        val current = client ?: return reconnectNow()
        forcedClose = true
        skipBackoff = true
        current.close()
    }

    /** Runs [body] on the live session; LinkCallException.Offline(machine.name) unless Online. Errors of [body] pass. */
    suspend fun <T> call(body: suspend (LinkSession) -> T): T {
        val current = client
        if (state != MachineLinkState.Online || current == null) throw LinkCallException.Offline(machine.name)
        return body(current)
    }

    /**
     * Asks the live session for the workspace list again, and takes the answer when it is newer than the list held (a
     * pull to refresh). Does nothing unless the Mac is Online and lists workspaces. A failed call leaves the list as it
     * was and the session open.
     */
    suspend fun refreshWorkspaces() {
        val current = client
        if (state != MachineLinkState.Online || !workspacesSupported || current == null) return
        try {
            val list = current.workspaces()
            // A change may have been applied while waiting: never go back to an older list.
            if (list.revision <= workspaces.revision) return
            workspaces = workspaces.reset(list.revision, list.workspaces)
            emit(MachineEvent.Workspaces(workspaces, workspacesSupported))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CoreLog.log("link_workspaces_refresh_failed")
        }
    }

    // Loop

    private suspend fun run() {
        try {
            while (currentCoroutineContext().isActive) {
                try {
                    val session = connector.connect(machine)
                    client = session
                    // The session is open: the failure count starts over.
                    failures = 0
                    currentCoroutineContext().ensureActive()
                    establish(session)
                    read(session)
                    session.close()
                    client = null
                    forcedClose = false
                    if (!currentCoroutineContext().isActive) break
                    sessionEnded()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    closeClient()
                    if (!currentCoroutineContext().isActive) break
                    if (forcedClose) {
                        // forceReconnect() dropped an attempt still syncing: start over at once.
                        forcedClose = false
                    } else if (!keepTrying(e)) {
                        break
                    }
                }
                waitBeforeRetry()
            }
        } finally {
            closeClient()
            ended = true
            output.close()
        }
    }

    private fun closeClient() {
        val current = client ?: return
        client = null
        current.close()
    }

    private suspend fun establish(session: LinkSession) {
        val snapshot = session.snapshot()
        val list: SessionList? = try {
            session.sessions()
        } catch (e: LinkClientException.Remote) {
            if (e.code != "unsupported") throw e
            null
        }
        val workspaceList = workspaceList(session)
        pending = pending.reset(snapshot.revision, snapshot.pending)
        sessions = sessions.reset(list?.revision ?: 0, list?.sessions ?: emptyList())
        sessionsSupported = list != null
        workspaces = workspaces.reset(workspaceList?.revision ?: 0, workspaceList?.workspaces ?: emptyList())
        workspacesSupported = workspaceList != null
        lostAtMs = null
        skipBackoff = false
        state = MachineLinkState.Online
        emit(MachineEvent.Pending(pending, actionable = true))
        emit(MachineEvent.Sessions(sessions, sessionsSupported))
        emit(MachineEvent.Workspaces(workspaces, workspacesSupported))
        emit(MachineEvent.Features(session.hostFeatures))
        emit(MachineEvent.State(MachineLinkState.Online))
    }

    /**
     * The Mac's workspace list, or null when it has none to give: it did not list the `workspaces` feature, or it
     * listed it and answered with an error (`unsupported`, `too_large`). Either way the session stays: it carries the
     * requests the user has to answer. A timeout or a closed session still ends the round.
     */
    private suspend fun workspaceList(session: LinkSession): WorkspaceList? {
        if (ShellXLink.WORKSPACES_FEATURE !in session.hostFeatures) return null
        return try {
            session.workspaces()
        } catch (e: LinkClientException.Remote) {
            CoreLog.log("link_workspaces_unavailable")
            null
        }
    }

    /** Reads the session's four streams until `changes` ends (the session is over). */
    private suspend fun read(session: LinkSession) {
        coroutineScope {
            val readers = listOf(
                launch { session.sessionChanges.collect { applySessions(it, session) } },
                launch { session.workspaceChanges.collect { applyWorkspaces(it, session) } },
                launch {
                    // Read even when no screen shows chat: the session buffers without bound. A reset stays in order
                    // with the entries around it.
                    session.chatEntries.collect { push ->
                        when (push) {
                            is ChatPush.Upsert -> emit(MachineEvent.Chat(push.sessionId, push.entries))
                            is ChatPush.Reset -> emit(MachineEvent.ChatReset(push.sessionId))
                        }
                    }
                },
            )
            session.changes.collect { applyPending(it, session) }
            readers.forEach { it.cancel() }
        }
    }

    private suspend fun applyPending(change: PendingChange, session: LinkSession) {
        val revised = pending.apply(change.revision, change.added, change.resolved)
        when (revised.result) {
            RevisionGate.Result.APPLIED -> {
                pending = revised.value
                val now = clock.nowMs()
                for (item in change.added) latency.record(LatencyMetric.PENDING_ARRIVAL, (now - item.createdAtMs).milliseconds)
                emit(MachineEvent.Pending(pending, actionable = state == MachineLinkState.Online))
            }
            RevisionGate.Result.IGNORED -> Unit
            RevisionGate.Result.GAP -> resync(session) {
                val snapshot = session.snapshot()
                pending = pending.reset(snapshot.revision, snapshot.pending)
                emit(MachineEvent.Pending(pending, actionable = state == MachineLinkState.Online))
            }
        }
    }

    private suspend fun applySessions(change: SessionChange, session: LinkSession) {
        val before = sessions
        val revised = sessions.apply(change.revision, change.upserted, change.removed)
        when (revised.result) {
            RevisionGate.Result.APPLIED -> {
                sessions = revised.value
                val now = clock.nowMs()
                for (upserted in change.upserted) recordStateChange(before, upserted, now)
                emit(MachineEvent.Sessions(sessions, sessionsSupported))
            }
            RevisionGate.Result.IGNORED -> Unit
            RevisionGate.Result.GAP -> resync(session) {
                val list = session.sessions()
                sessions = sessions.reset(list.revision, list.sessions)
                emit(MachineEvent.Sessions(sessions, sessionsSupported))
            }
        }
    }

    private fun recordStateChange(before: SessionSet, session: AgentSession, nowMs: Long) {
        if (before.session(session.sessionId)?.state == session.state) return
        val since = session.stateSinceMs ?: return
        latency.record(LatencyMetric.SESSION_CHANGE_ARRIVAL, (nowMs - since).milliseconds)
    }

    private suspend fun applyWorkspaces(change: WorkspaceChange, session: LinkSession) {
        // A Mac whose list could not be read may still push changes: without a list to apply them to, the first one
        // looks like a gap and its refetch would fail again, which would end the session at every change (or show a
        // partial list, at revision 0).
        if (!workspacesSupported) return
        val revised = workspaces.apply(change.revision, change.upserted, change.removed)
        when (revised.result) {
            RevisionGate.Result.APPLIED -> {
                workspaces = revised.value
                emit(MachineEvent.Workspaces(workspaces, workspacesSupported))
            }
            RevisionGate.Result.IGNORED -> Unit
            RevisionGate.Result.GAP -> resync(session) {
                val list = session.workspaces()
                workspaces = workspaces.reset(list.revision, list.workspaces)
                emit(MachineEvent.Workspaces(workspaces, workspacesSupported))
            }
        }
    }

    /** Runs a resync; when it fails, ends the session, so the next round starts from a snapshot. */
    private suspend fun resync(session: LinkSession, body: suspend () -> Unit) {
        try {
            body()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            CoreLog.log("link_resync_failed")
            session.close()
        }
    }

    private fun sessionEnded() {
        lostAtMs = clock.nowMs()
        failures = 1
        state = MachineLinkState.Reconnecting
        emit(MachineEvent.Pending(pending, actionable = false))
        emit(MachineEvent.State(MachineLinkState.Reconnecting))
    }

    /** Records a failed round. Returns false when the loop must stop. */
    private fun keepTrying(error: Exception): Boolean = when (LinkFailure.of(error)) {
        LinkFailure.OFFLINE -> {
            CoreLog.log("link_attempt_failed")
            failures += 1
            if (state !is MachineLinkState.Offline) {
                // Nothing is synced any more: drop the items.
                pending = pending.reset(0, emptyList())
                state = MachineLinkState.Offline(lostAtMs ?: clock.nowMs())
                emit(MachineEvent.Pending(pending, actionable = false))
                emit(MachineEvent.State(state))
            }
            true
        }
        LinkFailure.SIGNED_OUT -> {
            CoreLog.log("link_stopped signed_out")
            pending = pending.reset(0, emptyList())
            state = MachineLinkState.Offline(lostAtMs ?: clock.nowMs())
            emit(MachineEvent.Pending(pending, actionable = false))
            emit(MachineEvent.State(state))
            emit(MachineEvent.SignedOut)
            false
        }
        LinkFailure.REVOKED -> stopFor(MachineLinkState.Revoked, "revoked")
        LinkFailure.HOST_KEY_CHANGED -> stopFor(MachineLinkState.HostKeyChanged, "host_key_changed")
        LinkFailure.NEEDS_UPDATE -> stopFor(MachineLinkState.NeedsUpdate, "needs_update")
    }

    /** Ends in a terminal state: nothing from this Mac can be trusted or synced any more. */
    private fun stopFor(final: MachineLinkState, code: String): Boolean {
        CoreLog.log("link_stopped $code")
        pending = pending.reset(0, emptyList())
        sessions = sessions.reset(0, emptyList())
        workspaces = workspaces.reset(0, emptyList())
        state = final
        emit(MachineEvent.Pending(pending, actionable = false))
        emit(MachineEvent.Sessions(sessions, sessionsSupported))
        // The state first: a workspace screen that sees the list emptied must already know the Mac is not online, or
        // it would take the empty list for workspaces closed on the Mac.
        emit(MachineEvent.State(final))
        emit(MachineEvent.Workspaces(workspaces, workspacesSupported))
        return false
    }

    /** The backoff wait is a child job of the loop: [reconnectNow] cancels it, and the loop goes on at once. */
    private suspend fun waitBeforeRetry() {
        if (!currentCoroutineContext().isActive) return
        if (skipBackoff) {
            skipBackoff = false
            return
        }
        val delay = schedule.delay(failures, Random.nextDouble(-1.0, 1.0))
        try {
            coroutineScope {
                backoffWait = launch {
                    try {
                        sleep(delay)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        // A sleep that fails ends the wait early, as Swift's `try?` does.
                    }
                }
            }
        } finally {
            backoffWait = null
        }
    }

    private fun emit(event: MachineEvent) {
        output.trySend(event)
    }
}
