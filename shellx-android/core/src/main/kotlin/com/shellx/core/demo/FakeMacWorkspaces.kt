package com.shellx.core.demo

import com.shellx.core.text.utf8Size
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkCodec
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.WorkspaceChange
import com.shellx.link.core.WorkspaceList

/**
 * [FakeMac]'s workspaces (FakeMacWorkspaces.swift). Every member takes the Mac's lock. A Mac that lists no workspaces
 * ([pushes] false) still counts revisions but pushes nothing, as a host without a workspace source.
 */
internal class FakeMacWorkspaces(private val live: FakeMacLive, private val pushes: Boolean) {
    private val lock = live.lock
    private val byId = HashMap<String, LinkWorkspace>()
    private var revision = 0L
    private var lists = 0

    val listCount: Int get() = synchronized(lock) { lists }

    /** Replaces the list; what differs from the old one goes out as one change. Nothing differs: no change. */
    fun set(workspaces: List<LinkWorkspace>) {
        synchronized(lock) {
            val new = workspaces.associateBy { it.workspaceId }
            val upserted = sorted(new.values.filter { byId[it.workspaceId] != it })
            val removed = byId.keys.filter { it !in new }.sorted()
            byId.clear()
            byId.putAll(new)
            if (upserted.isEmpty() && removed.isEmpty()) return
            broadcastLocked(upserted, removed)
        }
    }

    fun upsert(workspace: LinkWorkspace) {
        synchronized(lock) {
            byId[workspace.workspaceId] = workspace
            broadcastLocked(listOf(workspace), emptyList())
        }
    }

    fun remove(workspaceId: String) {
        synchronized(lock) {
            if (byId.remove(workspaceId) == null) return
            broadcastLocked(emptyList(), listOf(workspaceId))
        }
    }

    /** Raises the revision without telling anyone, so the next change skips one. */
    fun skipRevision() {
        synchronized(lock) { revision += 1 }
    }

    /** The list in the Mac's sidebar order, or `too_large` when its titles alone do not fit in one frame. */
    fun list(): WorkspaceList = synchronized(lock) {
        lists += 1
        if (byId.values.sumOf { it.title.utf8Size } > LinkCodec.MAX_FRAME_BYTES) {
            throw LinkClientException.Remote("too_large", "the answer does not fit in one frame")
        }
        WorkspaceList(revision, sorted(byId.values))
    }

    private fun broadcastLocked(upserted: List<LinkWorkspace>, removed: List<String>) {
        revision += 1
        if (!pushes) return
        val change = WorkspaceChange(revision, upserted, removed)
        live.broadcastLocked { it.workspaceQueue.trySend(change) }
    }

    private fun sorted(workspaces: Collection<LinkWorkspace>): List<LinkWorkspace> =
        workspaces.sortedWith(compareBy<LinkWorkspace> { it.order }.thenBy { it.workspaceId })
}
