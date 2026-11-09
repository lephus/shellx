package com.shellx.core.terminal

import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.link.MachineLinkState
import com.shellx.core.workspaces.WorkspaceCommandResult
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.TerminalViewPush
import kotlin.time.Duration
import kotlinx.coroutines.flow.Flow

/** What the hub tells a terminal page (TerminalLink.swift), in the order it took it from the Mac. */
sealed interface TerminalHubEvent {
    /** A push of the Mac's live session (`LinkSession.terminalPushes`), as the session's bounded queue gave it. */
    data class Push(val machineId: String, val push: TerminalViewPush) : TerminalHubEvent

    /** The Mac's link state changed. Online comes again after every reconnect; a view opened before it is gone. */
    data class State(val machineId: String, val state: MachineLinkState) : TerminalHubEvent
}

/** How a `terminal.view.open` went. */
sealed interface TerminalOpenResult {
    data class Outcome(val outcome: TerminalViewOpenOutcome) : TerminalOpenResult

    /** Nothing was sent: the Mac is not online or does not list terminal_view. */
    data object NotSent : TerminalOpenResult

    /** Sent, but no answer came: the session ended or the call timed out. */
    data object NoAnswer : TerminalOpenResult
}

/** How a `terminal.create` went; [terminalId] is the new tab's id, only with an Ok [result]. */
data class TerminalCreation(val result: WorkspaceCommandResult, val terminalId: String?)

/** Main-confined. The hub as a terminal page uses it; MachineHub is the real one, tests script one. */
interface TerminalLink {
    /**
     * The terminal pushes and link states of the Mac [machineId], from the moment a collection starts (plan 3G
     * Decision 1; the iPhone's `terminalEvents()` covers every Mac). Each collection is one subscriber, until it ends;
     * nothing is replayed, the Mac's state at the start included (read [isOnline]).
     *
     * - **Pushes** come straight from the session's bounded queue (link-core's `TerminalPushQueue`) to the collector's
     *   code, unfiltered: nothing between them buffers, so a flood stays within the queue's bound and turns into one
     *   resync, and a collection cancelled and started again loses no push. Collect it directly into the assembler: no
     *   `buffer`, `flowOn`, `shareIn`, `produceIn` or other operator built on a channel or on `flow {}` in between, and
     *   no suspension in the collector's code. Only the newest collection of a Mac takes its pushes; an older one gets
     *   only the states until the newer one ends, then takes them again where it stopped. Pushes made while nobody
     *   collects are dropped, unless a collection starts in the same main-loop turn as the last one ended (a restarted
     *   effect): that one goes on where the other stopped.
     * - **States** are the newest the hub set, not each one in between; but a collection told Online for a session
     *   is always told a state that is not Online (Reconnecting, when the Mac is back already) before it is told Online
     *   for the next one, and Online before that session's first push.
     *
     * Completes when the hub stops.
     */
    fun terminalEvents(machineId: String): Flow<TerminalHubEvent>

    fun isOnline(machineId: String): Boolean

    /** True when the Mac listed `terminal_view` when it was last online. */
    fun supportsTerminalView(machineId: String): Boolean

    suspend fun openTerminalView(machineId: String, terminalId: String, cols: Int, rows: Int): TerminalOpenResult

    suspend fun closeTerminalView(machineId: String, terminalId: String)

    suspend fun sendTerminalInput(machineId: String, terminalId: String, units: List<TerminalInputUnit>)

    suspend fun resizeTerminalView(machineId: String, terminalId: String, cols: Int, rows: Int)

    suspend fun resyncTerminalView(machineId: String, terminalId: String)

    fun recordLatency(metric: LatencyMetric, duration: Duration)
}
