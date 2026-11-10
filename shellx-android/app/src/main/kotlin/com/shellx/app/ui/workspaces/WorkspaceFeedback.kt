package com.shellx.app.ui.workspaces

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.shellx.app.R
import com.shellx.app.ui.components.ConfirmDialog
import com.shellx.app.ui.components.MessageDialog
import com.shellx.core.workspaces.WorkspaceCommandResult
import com.shellx.core.workspaces.WorkspaceRef

/** The commands the list and the workspace screen send to a Mac. */
enum class WorkspaceCommand {
    CREATE,
    RENAME,
    CLOSE,

    /** Closes the terminal tab an agent runs in (`MachineHub.closeAgent`). */
    CLOSE_AGENT,

    /** Closes one terminal tab of a workspace (`MachineHub.closeTerminal`). */
    CLOSE_TAB,

    /** Opens a terminal tab in the workspace (`MachineHub.createTerminal`). */
    CREATE_TERMINAL,
}

/** What the list says when a command did not simply work. The words always say what to do next. */
enum class WorkspaceAlert(@StringRes val message: Int) {
    OFFLINE(R.string.workspaces_alert_offline),
    REFUSED_CLOSE(R.string.workspaces_alert_refused_close),
    REFUSED_CONTROL(R.string.workspaces_alert_refused_control),

    /** The Mac would not close an agent's tab: remote control is blocked, the tab is pinned, or it is the last of a
     *  workspace the Mac keeps. */
    REFUSED_CLOSE_AGENT(R.string.workspaces_alert_refused_close_agent),

    /** The Mac has no terminal tab for the agent, or the agent has stopped already. */
    AGENT_NOT_CLOSABLE(R.string.workspaces_alert_agent_not_closable),
    REFUSED_CLOSE_TAB(R.string.workspaces_alert_refused_close_tab),

    /** The Mac no longer has the tab. */
    TAB_NOT_CLOSABLE(R.string.workspaces_alert_tab_not_closable),
    FAILED(R.string.workspaces_alert_failed),
    UNKNOWN(R.string.workspaces_alert_unknown),
}

/** What the list does with a Mac's answer to a command (`WorkspaceFeedback.swift`). */
sealed interface WorkspaceFeedback {
    /** Nothing to show: the row arrives, changes or leaves by the Mac's push. */
    data object None : WorkspaceFeedback

    /** Opens the workspace just made. */
    data class Open(val ref: WorkspaceRef) : WorkspaceFeedback

    /** The Mac has no such workspace: asks for its list again, with no word to the user. */
    data object Refresh : WorkspaceFeedback

    data class Alert(val alert: WorkspaceAlert) : WorkspaceFeedback

    companion object {
        /** The feedback for [result] of [command] on the Mac [machineId]. */
        fun of(result: WorkspaceCommandResult, command: WorkspaceCommand, machineId: String): WorkspaceFeedback =
            when (result) {
                // A create the Mac answered without an id stays on the list: the new row arrives by push.
                is WorkspaceCommandResult.Ok -> {
                    val id = result.workspaceId
                    if (command == WorkspaceCommand.CREATE && id != null) Open(WorkspaceRef(machineId, id)) else None
                }
                // An agent or a tab the Mac cannot close: say why rather than refresh without a word.
                WorkspaceCommandResult.NotFound -> when (command) {
                    WorkspaceCommand.CLOSE_AGENT -> Alert(WorkspaceAlert.AGENT_NOT_CLOSABLE)
                    WorkspaceCommand.CLOSE_TAB -> Alert(WorkspaceAlert.TAB_NOT_CLOSABLE)
                    WorkspaceCommand.CREATE, WorkspaceCommand.RENAME, WorkspaceCommand.CLOSE, WorkspaceCommand.CREATE_TERMINAL -> Refresh
                }
                // Not only blocked remote control: the Mac's own rules can keep the tab too.
                WorkspaceCommandResult.Refused -> when (command) {
                    WorkspaceCommand.CLOSE -> Alert(WorkspaceAlert.REFUSED_CLOSE)
                    WorkspaceCommand.CLOSE_AGENT -> Alert(WorkspaceAlert.REFUSED_CLOSE_AGENT)
                    WorkspaceCommand.CLOSE_TAB -> Alert(WorkspaceAlert.REFUSED_CLOSE_TAB)
                    WorkspaceCommand.CREATE, WorkspaceCommand.RENAME, WorkspaceCommand.CREATE_TERMINAL -> Alert(WorkspaceAlert.REFUSED_CONTROL)
                }
                WorkspaceCommandResult.Failed -> Alert(WorkspaceAlert.FAILED)
                WorkspaceCommandResult.Offline -> Alert(WorkspaceAlert.OFFLINE)
                WorkspaceCommandResult.Unknown -> Alert(WorkspaceAlert.UNKNOWN)
            }
    }
}

/** Shows [alert], when there is one, with its words and OK. The list and the workspace screen say the same words for
 *  the same answer. */
@Composable
fun WorkspaceAlertDialog(alert: WorkspaceAlert?, dismiss: () -> Unit) {
    if (alert == null) return
    MessageDialog(title = null, text = stringResource(alert.message), onDismiss = dismiss)
}

/**
 * Asks before an agent is closed: "Close <name>?", what closing does on the Mac, and one red Close beside Cancel.
 * Nothing while [name] is null. The home's cards and the agent screen ask the same way.
 */
@Composable
fun AgentCloseConfirmation(name: String?, close: () -> Unit, dismiss: () -> Unit) {
    if (name == null) return
    ConfirmDialog(
        title = stringResource(R.string.agent_close_title, name),
        text = stringResource(R.string.agent_close_confirm),
        confirmLabel = stringResource(R.string.agent_close),
        onConfirm = close,
        onDismiss = dismiss,
    )
}
