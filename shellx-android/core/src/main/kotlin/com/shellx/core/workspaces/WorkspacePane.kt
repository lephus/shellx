package com.shellx.core.workspaces

import com.shellx.core.link.MachineSession
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace

/**
 * One chip of the workspace screen: a terminal of the workspace ([id] is the terminal's id on the Mac, [title] the
 * tab's name), and the agent running in it when the hub lists that agent's session. [session] is the session the
 * terminal names (`LinkTerminal.sessionId`), as its Mac lists it: null for a shell, and for a terminal that names a
 * session the Mac does not list (any more): that one shows as a shell, never as a chat with nothing behind it. The
 * title never prints.
 */
data class WorkspacePane(val id: String, val title: String, val session: MachineSession? = null) {
    /** The pane is an agent's chat; any other is a shell. */
    val isAgent: Boolean get() = session != null

    override fun toString(): String = "WorkspacePane(id=$id, title=<redacted>, session=$session)"

    companion object {
        /** The terminals of [workspace] as panes, in the Mac's order (`order`, then id). [session] gives the session a
         *  terminal names, if the hub lists it. */
        internal fun panes(workspace: LinkWorkspace, session: (String) -> MachineSession?): List<WorkspacePane> =
            ordered(workspace.terminals).map { terminal ->
                WorkspacePane(terminal.terminalId, terminal.title, terminal.sessionId?.let(session))
            }

        /** [terminals] by `order`; two at the same position by id, so the chips do not shuffle between two answers. */
        internal fun ordered(terminals: List<LinkTerminal>): List<LinkTerminal> =
            terminals.sortedWith(compareBy<LinkTerminal> { it.order }.thenBy { it.terminalId })
    }
}
