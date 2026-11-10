package com.shellx.core.link

import com.shellx.core.platform.CoreLog
import com.shellx.core.terminal.TerminalCreation
import com.shellx.core.terminal.TerminalHubEvent
import com.shellx.core.terminal.TerminalOpenResult
import com.shellx.core.workspaces.WorkspaceCommandResult
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkSession
import com.shellx.link.core.ShellXLink
import com.shellx.link.core.TerminalInputException
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.TerminalViewPush
import com.shellx.link.core.WorkspaceControlOutcome
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.FlowCollector
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.job

/**
 * The terminal view calls (PROTOCOL.md section 11) on each Mac's live session, and the terminal events of each Mac
 * (MachineHub+Terminal.swift). Nothing is sent to a Mac that is not online or that did not list `terminal_view`.
 * Main-confined, like the hub.
 *
 * **How the pushes keep their bound (plan 3G Decision 1).** The iPhone's hub reads every session's terminal pushes
 * and fans them out to unbounded streams. Here nothing between the session's `TerminalPushQueue` (link-core, at most
 * 2 MiB of frames plus one snapshot) and a page's assembler holds a push: [events] hands the page each push it takes
 * from the queue, in the page's own coroutine, and the connection never reads them. So a page that falls behind leaves
 * the frames in the queue, which drops what goes over the bound and puts one LOST part in their place (one resync); and
 * a page whose collection is cancelled and started again (STOP, then START) goes on where it stopped, since the queue
 * gives a cancelled collector nothing more. The fan-out is of states only (a conflated counter wakes the collectors).
 *
 * Per Mac, the newest collection takes the pushes; an older one waits, getting only states, and takes them again when
 * the newer one ends: a session views one terminal, and two collectors of one queue would split its frames. While no
 * collection runs, the pushes wait in the bounded queue for the next one (review B1 I-1): a page may send its open
 * before its collection starts, and the open's `Opened` and first snapshot must still reach it. What waits is harmless
 * to a page: it ignores other terminals and frames before its view's `Opened`, and the queue starts a view afresh at
 * each `Opened` and drops a terminal's queued frames at its next snapshot.
 */
internal class HubTerminals(private val hub: MachineHub) {
    private class Feed {
        /** The Mac's link state as the hub set it last; null before the first. */
        var state: MachineLinkState? = null

        /** Raised by one at each state the hub sets. */
        var stateVersion = 0L

        /** The live session's terminal pushes; null once the Mac is not Online. */
        var pushes: Flow<TerminalViewPush>? = null

        /** Raised by one for each session. */
        var generation = 0L

        /** The collections, oldest first: the last takes the pushes. */
        val subscribers = ArrayList<Subscriber>()
    }

    private class Subscriber {
        /** Its taking of a session's pushes, while it runs. */
        var taking: Job? = null

        /** True while its taking is being cancelled by [takeAway]. */
        var takenAway = false

        /** The session whose pushes it took to their end. */
        var finished = -1L

        /** Stops its taking before its next take: a newer collection, a session gone or the hub's stop. */
        fun takeAway() {
            val job = taking ?: return
            takenAway = true
            job.cancel()
        }
    }

    private val feeds = HashMap<String, Feed>()

    /** Raised at every change of a feed: wakes the collections, which compare what they were told. Conflated. */
    private val changes = MutableStateFlow(0L)
    private var stopped = false

    val subscriberCount: Int get() = feeds.values.sumOf { it.subscribers.size }

    fun events(machineId: String): Flow<TerminalHubEvent> = object : Flow<TerminalHubEvent> {
        override suspend fun collect(collector: FlowCollector<TerminalHubEvent>) = deliver(machineId, collector)
    }

    // What the hub tells it

    /** The hub set [state] for the Mac (apply, revoke, detachAll). Not Online: its session is gone. */
    fun stateChanged(machineId: String, state: MachineLinkState) {
        val feed = feed(machineId)
        feed.state = state
        feed.stateVersion += 1
        if (state != MachineLinkState.Online) {
            feed.pushes = null
            // What is left of the old session's pushes belongs to a view that is gone: tell the state now.
            feed.subscribers.lastOrNull()?.takeAway()
        }
        changed()
    }

    /** A new session of the Mac, with its terminal pushes; its Online follows. */
    fun sessionStarted(machineId: String, pushes: Flow<TerminalViewPush>) {
        val feed = feed(machineId)
        feed.pushes = pushes
        feed.generation += 1
        changed()
    }

    /** The hub stopped: every collection completes. */
    fun stop() {
        stopped = true
        for (feed in feeds.values) {
            for (subscriber in feed.subscribers) subscriber.takeAway()
        }
        changed()
    }

    // Calls

    fun isOnline(machineId: String): Boolean = hub.state.value.machine(machineId)?.state == MachineLinkState.Online

    fun supportsTerminalView(machineId: String): Boolean = hub.state.value.supportsTerminalView(machineId)

    /**
     * NotSent when the Mac is not online or did not list `terminal_view`, or nothing could be sent (LinkCallException);
     * the Mac's error answer → Outcome(FAILED); a timeout or a session that ended while waiting → NoAnswer.
     */
    suspend fun open(machineId: String, terminalId: String, cols: Int, rows: Int): TerminalOpenResult {
        if (!canView(machineId)) return TerminalOpenResult.NotSent
        return try {
            TerminalOpenResult.Outcome(hub.withLink(machineId) { it.openTerminalView(terminalId, cols, rows) })
        } catch (e: CancellationException) {
            throw e
        } catch (e: LinkCallException) {
            TerminalOpenResult.NotSent
        } catch (e: LinkClientException.Remote) {
            TerminalOpenResult.Outcome(TerminalViewOpenOutcome.FAILED)
        } catch (e: Exception) {
            TerminalOpenResult.NoAnswer
        }
    }

    /** Sends one terminal message that expects no answer, with [open]'s guard. Errors are logged (names only) and dropped. */
    suspend fun post(machineId: String, body: suspend (LinkSession) -> Unit) {
        if (!canView(machineId)) return
        try {
            hub.withLink(machineId, body)
        } catch (e: CancellationException) {
            throw e
        } catch (e: TerminalInputException) {
            CoreLog.log("terminal_input_refused")
        } catch (e: Exception) {
            CoreLog.log("terminal_send_failed")
        }
    }

    /** `terminal.create`, sent once like the workspace commands; the new id only with Ok. */
    suspend fun create(ref: WorkspaceRef): TerminalCreation {
        var made: String? = null
        val result = hub.workspaceCommand(ref.machineId, ShellXLink.TERMINAL_CREATE_FEATURE) { session ->
            val created = session.createTerminal(ref.workspaceId)
            if (created.outcome == WorkspaceControlOutcome.OK) made = created.terminalId
            WorkspaceCommandResult.of(created.outcome)
        }
        return TerminalCreation(result, made.takeIf { result is WorkspaceCommandResult.Ok })
    }

    private fun canView(machineId: String): Boolean = isOnline(machineId) && supportsTerminalView(machineId)

    // Events

    private suspend fun deliver(machineId: String, collector: FlowCollector<TerminalHubEvent>) {
        if (stopped) return
        val feed = feed(machineId)
        val me = Subscriber()
        // The newest takes the pushes: the one before it stops, before its next take. It is in the list first, so a
        // collection that resumes inside takeAway (an immediate dispatcher) already sees it.
        val previous = feed.subscribers.lastOrNull()
        feed.subscribers += me
        previous?.takeAway()
        // Nothing is replayed: what holds now counts as told.
        var toldVersion = feed.stateVersion
        var toldOnline: Long? = if (feed.state == MachineLinkState.Online) feed.generation else null
        try {
            while (!stopped) {
                val seen = changes.value
                val online = feed.state == MachineLinkState.Online
                val known = toldOnline
                if (known != null && (!online || feed.generation != known)) {
                    // The session this collection was told of is gone; when the Mac is back already, it passed through
                    // Reconnecting, which is what is told first.
                    toldOnline = null
                    val state = if (online) MachineLinkState.Reconnecting else feed.state ?: MachineLinkState.Reconnecting
                    if (!online) toldVersion = feed.stateVersion
                    collector.emit(TerminalHubEvent.State(machineId, state))
                    continue
                }
                val state = feed.state
                if (feed.stateVersion != toldVersion && state != null) {
                    toldVersion = feed.stateVersion
                    if (online) toldOnline = feed.generation
                    collector.emit(TerminalHubEvent.State(machineId, state))
                    continue
                }
                val pushes = feed.pushes
                if (online && pushes != null && toldOnline == feed.generation && me.finished != feed.generation &&
                    feed.subscribers.lastOrNull() === me
                ) {
                    val generation = feed.generation
                    if (take(pushes, me, machineId, collector)) me.finished = generation
                    continue
                }
                changes.first { it != seen }
            }
        } finally {
            me.takeAway()
            feed.subscribers -= me
            changed()
        }
    }

    /**
     * Hands [pushes] to [collector] in this coroutine until they end (true: the session ended), or until [me] stops
     * being the newest collection, the session goes or the hub stops (false).
     */
    private suspend fun take(
        pushes: Flow<TerminalViewPush>,
        me: Subscriber,
        machineId: String,
        collector: FlowCollector<TerminalHubEvent>,
    ): Boolean {
        try {
            coroutineScope {
                me.taking = coroutineContext.job
                pushes.collect { collector.emit(TerminalHubEvent.Push(machineId, it)) }
            }
            return true
        } catch (e: CancellationException) {
            // Only [Subscriber.takeAway]'s cancellation stops here; the collection's own, or a collector's abort, goes on.
            if (!me.takenAway) throw e
            currentCoroutineContext().ensureActive()
            return false
        } finally {
            me.taking = null
            me.takenAway = false
        }
    }

    private fun feed(machineId: String): Feed = feeds.getOrPut(machineId) { Feed() }

    private fun changed() {
        changes.value += 1
    }
}
