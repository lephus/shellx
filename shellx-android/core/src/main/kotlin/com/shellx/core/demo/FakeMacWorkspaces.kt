package com.shellx.core.demo

import com.shellx.core.text.utf8Size
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkCodec
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.WorkspaceChange
import com.shellx.link.core.WorkspaceControlOutcome
import com.shellx.link.core.WorkspaceCreated
import com.shellx.link.core.WorkspaceList

/**
 * [FakeMac]'s workspaces (FakeMacWorkspaces.swift). Every member takes the Mac's lock. A Mac that lists no workspaces
 * ([pushes] false) still counts revisions but pushes nothing, as a host without a workspace source.
 *
 * Control acts the way the real Mac does, unless a `setNext…Outcome` says otherwise for the next call: a created
 * workspace is added with one terminal, a rename and a close need a workspace the list holds (else `NOT_FOUND`), and
 * the last workspace is never closed (`REFUSED`). Closing an agent needs a session the Mac lists that has not ended;
 * it turns `ENDED` and goes out as a session change. Closing a terminal needs a terminal the named workspace lists;
 * the workspace goes with its last terminal. [hold] holds all three kinds of call.
 */
internal class FakeMacWorkspaces(
    private val live: FakeMacLive,
    private val pushes: Boolean,
    private val sessions: FakeMacSessions,
    private val nowMs: () -> Long,
) {
    private val lock = live.lock
    private val byId = HashMap<String, LinkWorkspace>()
    private var revision = 0L
    private var lists = 0
    private val calls = ArrayList<String>()
    private var nextOutcome: WorkspaceControlOutcome? = null
    private var created = 0
    private var addedTerminals = 0
    private val agentCalls = ArrayList<String>()
    private var nextAgentOutcome: WorkspaceControlOutcome? = null
    private val terminalCalls = ArrayList<FakeMac.TerminalCloseCall>()
    private var nextTerminalOutcome: WorkspaceControlOutcome? = null

    /** Control calls (workspace, agent and terminal) are recorded, then wait while it holds. */
    val hold = FakeMacHold(lock)

    val listCount: Int get() = synchronized(lock) { lists }
    val controlCalls: List<String> get() = synchronized(lock) { calls.toList() }
    val agentCloses: List<String> get() = synchronized(lock) { agentCalls.toList() }
    val terminalCloses: List<FakeMac.TerminalCloseCall> get() = synchronized(lock) { terminalCalls.toList() }

    fun setNextOutcome(outcome: WorkspaceControlOutcome) {
        synchronized(lock) { nextOutcome = outcome }
    }

    fun setNextAgentCloseOutcome(outcome: WorkspaceControlOutcome) {
        synchronized(lock) { nextAgentOutcome = outcome }
    }

    fun setNextTerminalCloseOutcome(outcome: WorkspaceControlOutcome) {
        synchronized(lock) { nextTerminalOutcome = outcome }
    }

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

    /** True when a workspace the Mac lists holds [terminalId]. */
    fun listsTerminal(terminalId: String): Boolean = synchronized(lock) {
        byId.values.any { workspace -> workspace.terminals.any { it.terminalId == terminalId } }
    }

    /**
     * Appends `LinkTerminal("<workspaceId>-new-<n>" (n = 1, 2, … over the Mac's life), "zsh", the workspace's last order
     * + 1, selected = false)` and broadcasts the change; null for a workspace the Mac does not list.
     */
    fun addTerminal(workspaceId: String): String? = synchronized(lock) {
        val workspace = byId[workspaceId] ?: return null
        addedTerminals += 1
        val id = "$workspaceId-new-$addedTerminals"
        val order = (workspace.terminals.maxOfOrNull { it.order } ?: -1) + 1
        val grown = workspace.copy(terminals = workspace.terminals + LinkTerminal(id, "zsh", order, selected = false))
        byId[workspaceId] = grown
        broadcastLocked(listOf(grown), emptyList())
        id
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

    suspend fun create(): WorkspaceCreated {
        synchronized(lock) { calls += "create" }
        hold.pass()
        return synchronized(lock) {
            takeOutcomeLocked()?.takeIf { it != WorkspaceControlOutcome.OK }?.let { return WorkspaceCreated(it, null) }
            created += 1
            val id = "ws-new-$created"
            val workspace = LinkWorkspace(
                workspaceId = id, title = "Workspace $created", order = (byId.values.maxOfOrNull { it.order } ?: -1) + 1,
                terminals = listOf(LinkTerminal(terminalId = "$id-t1", title = "zsh", order = 0, selected = true)),
            )
            byId[id] = workspace
            broadcastLocked(listOf(workspace), emptyList())
            WorkspaceCreated(WorkspaceControlOutcome.OK, id)
        }
    }

    suspend fun rename(workspaceId: String, title: String): WorkspaceControlOutcome {
        synchronized(lock) { calls += "rename:$workspaceId:$title" }
        hold.pass()
        return synchronized(lock) {
            takeOutcomeLocked()?.takeIf { it != WorkspaceControlOutcome.OK }?.let { return it }
            val workspace = byId[workspaceId] ?: return WorkspaceControlOutcome.NOT_FOUND
            val renamed = workspace.copy(title = title)
            byId[workspaceId] = renamed
            broadcastLocked(listOf(renamed), emptyList())
            WorkspaceControlOutcome.OK
        }
    }

    suspend fun close(workspaceId: String): WorkspaceControlOutcome {
        synchronized(lock) { calls += "close:$workspaceId" }
        hold.pass()
        return synchronized(lock) {
            takeOutcomeLocked()?.takeIf { it != WorkspaceControlOutcome.OK }?.let { return it }
            if (!byId.containsKey(workspaceId)) return WorkspaceControlOutcome.NOT_FOUND
            // The Mac's own rule: it keeps one workspace.
            if (byId.size <= 1) return WorkspaceControlOutcome.REFUSED
            byId.remove(workspaceId)
            broadcastLocked(emptyList(), listOf(workspaceId))
            WorkspaceControlOutcome.OK
        }
    }

    suspend fun closeAgent(sessionId: String): WorkspaceControlOutcome {
        synchronized(lock) { agentCalls += sessionId }
        hold.pass()
        return synchronized(lock) {
            val forced = nextAgentOutcome
            nextAgentOutcome = null
            if (forced != null && forced != WorkspaceControlOutcome.OK) return forced
            val session = sessions.session(sessionId)
            if (session == null || session.state == AgentState.ENDED) return WorkspaceControlOutcome.NOT_FOUND
            val now = nowMs()
            sessions.upsert(session.copy(state = AgentState.ENDED, stateSinceMs = now, lastActivityMs = now))
            WorkspaceControlOutcome.OK
        }
    }

    suspend fun closeTerminal(workspaceId: String, terminalId: String): WorkspaceControlOutcome {
        synchronized(lock) { terminalCalls += FakeMac.TerminalCloseCall(workspaceId, terminalId) }
        hold.pass()
        return synchronized(lock) {
            val forced = nextTerminalOutcome
            nextTerminalOutcome = null
            if (forced != null && forced != WorkspaceControlOutcome.OK) return forced
            val workspace = byId[workspaceId]
            if (workspace == null || workspace.terminals.none { it.terminalId == terminalId }) {
                return WorkspaceControlOutcome.NOT_FOUND
            }
            val left = workspace.copy(terminals = workspace.terminals.filter { it.terminalId != terminalId })
            if (left.terminals.isEmpty()) {
                byId.remove(workspaceId)
                broadcastLocked(emptyList(), listOf(workspaceId))
            } else {
                byId[workspaceId] = left
                broadcastLocked(listOf(left), emptyList())
            }
            WorkspaceControlOutcome.OK
        }
    }

    private fun takeOutcomeLocked(): WorkspaceControlOutcome? = nextOutcome.also { nextOutcome = null }

    private fun broadcastLocked(upserted: List<LinkWorkspace>, removed: List<String>) {
        revision += 1
        if (!pushes) return
        val change = WorkspaceChange(revision, upserted, removed)
        live.broadcastLocked { it.workspaceQueue.trySend(change) }
    }

    private fun sorted(workspaces: Collection<LinkWorkspace>): List<LinkWorkspace> =
        workspaces.sortedWith(compareBy<LinkWorkspace> { it.order }.thenBy { it.workspaceId })
}
