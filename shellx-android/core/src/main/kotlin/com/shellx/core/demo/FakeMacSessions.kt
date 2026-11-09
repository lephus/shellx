package com.shellx.core.demo

import com.shellx.link.core.AgentSession
import com.shellx.link.core.SessionChange
import com.shellx.link.core.SessionList

/**
 * [FakeMac]'s agent sessions (FakeMacSessions.swift). Every member takes the Mac's lock. A Mac that serves no sessions
 * ([pushes] false) still counts revisions but pushes nothing, as a host without a session source.
 */
internal class FakeMacSessions(private val live: FakeMacLive, private val pushes: Boolean) {
    private val lock = live.lock
    private val byId = HashMap<String, AgentSession>()
    private var revision = 0L
    private var lists = 0

    val listCount: Int get() = synchronized(lock) { lists }

    fun upsert(session: AgentSession) {
        synchronized(lock) {
            byId[session.sessionId] = session
            broadcastLocked(listOf(session), emptyList())
        }
    }

    fun remove(sessionId: String) {
        synchronized(lock) {
            if (byId.remove(sessionId) == null) return
            broadcastLocked(emptyList(), listOf(sessionId))
        }
    }

    /** Raises the revision without telling anyone, so the next change skips one. */
    fun skipRevision() {
        synchronized(lock) { revision += 1 }
    }

    fun session(sessionId: String): AgentSession? = synchronized(lock) { byId[sessionId] }

    fun list(): SessionList = synchronized(lock) {
        lists += 1
        SessionList(revision, byId.values.sortedBy { it.sessionId })
    }

    private fun broadcastLocked(upserted: List<AgentSession>, removed: List<String>) {
        revision += 1
        if (!pushes) return
        val change = SessionChange(revision, upserted, removed)
        live.broadcastLocked { it.sessionQueue.trySend(change) }
    }
}
