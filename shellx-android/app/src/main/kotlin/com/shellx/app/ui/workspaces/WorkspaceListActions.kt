package com.shellx.app.ui.workspaces

import androidx.compose.runtime.MutableState
import com.shellx.app.SignedInScope
import com.shellx.app.ui.nav.SessionListKind
import com.shellx.app.ui.nav.ShellXNavigator
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceCommandResult
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

    /**
     * The home's actions wired to [scope] (`WorkspaceListActions.make` in Swift):
     * - the toolbar, a Mac's header, a Mac's last row and the Ended fold go through [navigator];
     * - a workspace card opens its workspace and marks it seen (its agents leave "Just finished");
     * - ＋, rename and close run the hub's workspace commands in the hub's scope, and [WorkspaceFeedback] says what
     *   follows: a new workspace opens, a gone one refreshes the list, anything else goes to [alert];
     * - [creating] is true from ＋ until the Mac answered, so a second tap makes no second workspace;
     * - a confirmed Close on an agent card goes through [closeAgent];
     * - "Remove from This Phone" hides the session on this phone; nothing goes to the Mac.
     *
     * [done] gets each command's task, so a test can wait for it.
     */
    fun make(
        scope: SignedInScope,
        navigator: ShellXNavigator,
        alert: (WorkspaceAlert) -> Unit,
        creating: MutableState<Boolean>,
        done: (Deferred<WorkspaceFeedback>) -> Unit = {},
    ): WorkspaceListScreenActions {
        val hub = scope.hub
        fun run(command: WorkspaceCommand, machineId: String, call: suspend () -> WorkspaceCommandResult):
            Deferred<WorkspaceFeedback> {
            val task = hub.scope.async {
                val feedback = WorkspaceFeedback.of(call(), command, machineId)
                when (feedback) {
                    WorkspaceFeedback.None -> Unit
                    is WorkspaceFeedback.Open -> navigator.openWorkspace(feedback.ref)
                    WorkspaceFeedback.Refresh -> hub.refreshWorkspaces(machineId)
                    is WorkspaceFeedback.Alert -> alert(feedback.alert)
                }
                feedback
            }
            done(task)
            return task
        }
        return WorkspaceListScreenActions(
            openWorkspace = { ref ->
                hub.markSeen(ref)
                navigator.openWorkspace(ref)
            },
            create = create@{ machineId ->
                if (creating.value) return@create
                creating.value = true
                // Also when the hub's scope ended before the command started: ＋ never stays off.
                run(WorkspaceCommand.CREATE, machineId) { hub.createWorkspace(machineId) }
                    .invokeOnCompletion { creating.value = false }
            },
            rename = { ref, title -> run(WorkspaceCommand.RENAME, ref.machineId) { hub.renameWorkspace(ref, title) } },
            close = { ref -> run(WorkspaceCommand.CLOSE, ref.machineId) { hub.closeWorkspace(ref) } },
            closeAgent = { ref -> closeAgent(ref, hub, alert)?.let(done) },
            removeFromPhone = { session -> scope.goneRemovals.remove(session) },
            openAgent = navigator::openAgent,
            openPending = { navigator.openPending() },
            openSettings = navigator::openSettings,
            openMachines = navigator::openMachines,
            openOtherSessions = { machineId -> navigator.openSessions(SessionListKind.OTHER, machineId) },
            openEnded = { navigator.openSessions(SessionListKind.ENDED) },
            refresh = { hub.refreshWorkspaces() },
        )
    }
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
