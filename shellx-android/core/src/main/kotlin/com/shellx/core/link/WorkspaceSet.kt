package com.shellx.core.link

import com.shellx.link.core.LinkWorkspace

/**
 * One Mac's workspaces at a revision, in the order of the Mac's sidebar. Immutable.
 *
 * The revision is the workspace list's own counter, apart from the pending set's and the session list's
 * (PROTOCOL.md section 4, "Workspace").
 */
class WorkspaceSet(val revision: Long = 0, workspaces: List<LinkWorkspace> = emptyList()) {
    val workspaces: List<LinkWorkspace> = sorted(workspaces)

    /** The set replaced with a `workspace.list` answer. */
    fun reset(revision: Long, workspaces: List<LinkWorkspace>): WorkspaceSet = WorkspaceSet(revision, workspaces)

    /**
     * Applies a `workspace.changed` when it is the next revision; otherwise leaves the set as it was and says why
     * (PROTOCOL.md section 4). An upsert replaces the workspace with the same id, terminals and all.
     */
    fun apply(revision: Long, upserted: List<LinkWorkspace>, removed: List<String>): Revised<WorkspaceSet> {
        val result = RevisionGate.check(this.revision, revision)
        if (result != RevisionGate.Result.APPLIED) return Revised(this, result)
        val replaced = upserted.map { it.workspaceId }.toSet() + removed
        val gone = removed.toSet()
        val kept = workspaces.filter { it.workspaceId !in replaced } + upserted.filter { it.workspaceId !in gone }
        return Revised(WorkspaceSet(revision, kept), result)
    }

    /** The workspace with [id], if the set has it. */
    fun workspace(id: String): LinkWorkspace? = workspaces.firstOrNull { it.workspaceId == id }

    override fun equals(other: Any?): Boolean =
        other is WorkspaceSet && revision == other.revision && workspaces == other.workspaces

    override fun hashCode(): Int = revision.hashCode() * 31 + workspaces.hashCode()

    override fun toString(): String = "WorkspaceSet(revision=$revision, workspaces=$workspaces)"

    private companion object {
        /** By `order`; two workspaces at the same position (windows count apart) by id, so the list does not shuffle
         *  between two answers. */
        fun sorted(workspaces: List<LinkWorkspace>): List<LinkWorkspace> =
            workspaces.sortedWith(compareBy<LinkWorkspace> { it.order }.thenBy { it.workspaceId })
    }
}
