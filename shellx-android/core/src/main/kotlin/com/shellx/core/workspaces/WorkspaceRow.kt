package com.shellx.core.workspaces

import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.WorkspaceSet
import com.shellx.core.pending.previewText
import com.shellx.core.text.graphemeCount
import com.shellx.core.text.nonEmptyLines
import com.shellx.core.text.takeGraphemes
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkTerminal

/** What a workspace row says about the agents in it, most pressing first. */
enum class WorkspaceState {
    /** A request of the workspace waits for the user. */
    NEEDS_YOU,

    /** An agent in the workspace is working. */
    RUNNING,

    /** An agent in the workspace finished a turn and the user has not looked since. */
    DONE,

    /** Reserved: nothing reports an error yet. */
    ERROR,

    /** No agent, or none doing anything. */
    IDLE,
}

/** Points at one workspace on one Mac. */
data class WorkspaceRef(val machineId: String, val workspaceId: String)

/**
 * One line of a Mac's workspace list: the workspace as the Mac lists it, and a state worked out from the Mac's
 * sessions and pending requests. [question] is the first line of the first pending request of the workspace, while
 * [state] is NEEDS_YOU. The title, directory, branch and question never print.
 */
data class WorkspaceRow(
    val id: WorkspaceRef,
    val title: String,
    val directory: String? = null,
    val branch: String? = null,
    val ports: List<Int> = emptyList(),
    val state: WorkspaceState = WorkspaceState.IDLE,
    val question: String? = null,
    val terminals: List<LinkTerminal> = emptyList(),
) {
    override fun toString(): String = "WorkspaceRow(id=$id, title=<redacted>, directory=${redact(directory)}, " +
        "branch=${redact(branch)}, ports=$ports, state=$state, question=${redact(question)}, terminals=$terminals)"

    companion object {
        /** The longest `question`, in characters. */
        internal const val QUESTION_LENGTH = 140

        /**
         * The rows for [workspaces], in their order.
         *
         * The state, first match wins:
         * - NEEDS_YOU: a pending request of the workspace is waiting; `question` is the first line of the first one in
         *   [pending];
         * - RUNNING: a session of the workspace is `working`;
         * - DONE: a session of the workspace is in [finished], the ids `SessionFinishDetector` reported finished and
         *   the user has not seen since (`MachineHub.finishedSessionIds`);
         * - IDLE.
         *
         * A session is in a workspace when its own `workspaceId` is the workspace's, or a terminal of the workspace
         * names it (`LinkTerminal.sessionId`). [pending] of other Macs are left out.
         */
        fun rows(
            workspaces: WorkspaceSet,
            sessions: List<AgentSession>,
            pending: List<MachinePendingItem>,
            finished: Set<String>,
            machineId: String,
        ): List<WorkspaceRow> = workspaces.workspaces.map { workspace ->
            val mine = sessionIds(workspace.workspaceId, workspace.terminals, sessions)
            val request = pending.firstOrNull { it.isIn(machineId, workspace.workspaceId) }
            var question: String? = null
            val state = when {
                request != null -> {
                    question = request.item.previewText?.let(::firstLine)
                    WorkspaceState.NEEDS_YOU
                }
                sessions.any { it.sessionId in mine && it.state == AgentState.WORKING } -> WorkspaceState.RUNNING
                mine.any { it in finished } -> WorkspaceState.DONE
                else -> WorkspaceState.IDLE
            }
            WorkspaceRow(
                id = WorkspaceRef(machineId, workspace.workspaceId), title = workspace.title,
                directory = workspace.directory, branch = workspace.branch, ports = workspace.ports ?: emptyList(),
                state = state, question = question, terminals = workspace.terminals,
            )
        }

        /** The ids of the sessions in a workspace: those of [among] whose `workspaceId` is [workspaceId], and those
         *  one of its [terminals] names. */
        internal fun sessionIds(workspaceId: String, terminals: List<LinkTerminal>, among: List<AgentSession>): Set<String> {
            val named = terminals.mapNotNull { it.sessionId }.toSet()
            return among.filter { it.workspaceId == workspaceId || it.sessionId in named }.map { it.sessionId }.toSet()
        }

        /** The first non-blank line of [text], trimmed, cut to QUESTION_LENGTH characters (with "…"). */
        internal fun firstLine(text: String): String? {
            val line = text.nonEmptyLines().asSequence().map { it.trim() }.firstOrNull { it.isNotEmpty() } ?: return null
            if (line.graphemeCount() <= QUESTION_LENGTH) return line
            return line.takeGraphemes(QUESTION_LENGTH - 1) + "…"
        }

        private fun redact(value: String?): String = if (value == null) "null" else "<redacted>"
    }
}
