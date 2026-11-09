package com.shellx.app.ui.workspaces

import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.link.core.AgentState
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async

/**
 * What the list's controls do (`WorkspaceListActions` in `WorkspaceListView.swift`). Every Close Agent and Close Tab
 * goes through [closeAgent] and [closeTab] (the home here, plan 3E's agent and workspace screens), so a second tap, or
 * a swipe while a menu's close waits, sends nothing until the Mac answered the first. Main-confined.
 */
object WorkspaceListActions {
    /** A tab whose close is on its way: its Mac and its terminal id. */
    private data class ClosingTab(val machineId: String, val terminalId: String)

    private val lock = Any()
    private val closingAgents = HashSet<SessionRef>()
    private val closingTabs = HashSet<ClosingTab>()

    /**
     * An agent the phone may offer to close, the one rule for every Close Agent: its session has not ended (the
     * terminal of an agent that exited runs the user's shell), a tab of its Mac's listed workspaces names it (so an
     * agent outside workspaces has no Close), and its Mac listed `agent_close`.
     */
    fun canClose(session: MachineSession, hub: MachineHub): Boolean =
        session.session.state != AgentState.ENDED && hub.supportsAgentClose(session.machineId) &&
            hub.hasListedTerminal(session.ref)

    /**
     * Closes the agent of [ref] on its Mac once the user confirmed, in the hub's scope, unless a close of it waits for
     * the Mac already (then nothing is sent and the result is null). [WorkspaceFeedback] says what follows: nothing
     * when it worked (the session moves to Ended by the Mac's push), else an alert through [alert].
     */
    fun closeAgent(ref: SessionRef, hub: MachineHub, alert: (WorkspaceAlert) -> Unit): Deferred<WorkspaceFeedback>? {
        if (!synchronized(lock) { closingAgents.add(ref) }) return null
        val task = hub.scope.async {
            val feedback = WorkspaceFeedback.of(hub.closeAgent(ref), WorkspaceCommand.CLOSE_AGENT, ref.machineId)
            if (feedback is WorkspaceFeedback.Alert) alert(feedback.alert)
            feedback
        }
        // Also when the hub's scope ended before the close started: the key never stays behind.
        task.invokeOnCompletion { synchronized(lock) { closingAgents.remove(ref) } }
        return task
    }

    /** The phone may offer to close this Mac's tabs, agent or shell: it listed `terminal_close` when it was last
     *  online. */
    fun canCloseTab(machineId: String, hub: MachineHub): Boolean = hub.supportsTerminalClose(machineId)

    /**
     * Closes the tab [terminalId] of the workspace [workspaceId] on the Mac [machineId] once the user confirmed, in the
     * hub's scope, unless a close of it waits for the Mac already (then null). Nothing when it worked (the tab, or its
     * workspace when it was the last tab, leaves by the Mac's push), else an alert through [alert].
     */
    fun closeTab(
        machineId: String,
        workspaceId: String,
        terminalId: String,
        hub: MachineHub,
        alert: (WorkspaceAlert) -> Unit,
    ): Deferred<WorkspaceFeedback>? {
        val tab = ClosingTab(machineId, terminalId)
        if (!synchronized(lock) { closingTabs.add(tab) }) return null
        val task = hub.scope.async {
            val feedback = WorkspaceFeedback.of(
                hub.closeTerminal(machineId, workspaceId, terminalId), WorkspaceCommand.CLOSE_TAB, machineId,
            )
            if (feedback is WorkspaceFeedback.Alert) alert(feedback.alert)
            feedback
        }
        task.invokeOnCompletion { synchronized(lock) { closingTabs.remove(tab) } }
        return task
    }
}
