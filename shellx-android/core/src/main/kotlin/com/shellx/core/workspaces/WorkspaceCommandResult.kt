package com.shellx.core.workspaces

import com.shellx.link.core.WorkspaceControlOutcome

/** How a workspace command (make, rename, close) went, as `MachineHub` reports it. */
sealed interface WorkspaceCommandResult {
    /** The Mac did it. [workspaceId] is the new workspace's id after a create, null for the others. */
    data class Ok(val workspaceId: String?) : WorkspaceCommandResult

    /** The Mac has no such workspace, live agent session or terminal tab (in that workspace). */
    data object NotFound : WorkspaceCommandResult

    /** The Mac does not allow it: remote control is blocked, or its own rule says no (a pinned tab, a pinned
     *  workspace, or the last workspace of a window, stays). */
    data object Refused : WorkspaceCommandResult

    /** The Mac could not do it, or took no such command. */
    data object Failed : WorkspaceCommandResult

    /** The Mac is not online: nothing was sent. */
    data object Offline : WorkspaceCommandResult

    /** The command was sent but the answer is not known: the link dropped while waiting, or the Mac answered in a way
     *  this app does not know. It is not sent again (the Mac may have acted); the workspace list tells what became of
     *  it. */
    data object Unknown : WorkspaceCommandResult

    companion object {
        /** The result for the Mac's [outcome] and, for a create, the id of the new workspace. */
        internal fun of(outcome: WorkspaceControlOutcome, workspaceId: String? = null): WorkspaceCommandResult =
            when (outcome) {
                WorkspaceControlOutcome.OK -> Ok(workspaceId)
                WorkspaceControlOutcome.NOT_FOUND -> NotFound
                WorkspaceControlOutcome.REFUSED -> Refused
                WorkspaceControlOutcome.FAILED -> Failed
                else -> Unknown
            }
    }
}
