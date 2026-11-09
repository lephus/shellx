package com.shellx.core.link

import com.shellx.link.core.AgentSession

/** One Mac's agent sessions at a revision: most recent activity first (none last), then by `sessionId`. Immutable. */
class SessionSet(val revision: Long = 0, sessions: List<AgentSession> = emptyList()) {
    val sessions: List<AgentSession> = sorted(sessions)

    /** The set replaced with an `agent.sessions` answer. */
    fun reset(revision: Long, sessions: List<AgentSession>): SessionSet = SessionSet(revision, sessions)

    /**
     * Applies an `agent.sessions.changed` when it is the next revision; otherwise leaves the set as it was and says
     * why (PROTOCOL.md section 4).
     */
    fun apply(revision: Long, upserted: List<AgentSession>, removed: List<String>): Revised<SessionSet> {
        val result = RevisionGate.check(this.revision, revision)
        if (result != RevisionGate.Result.APPLIED) return Revised(this, result)
        val replaced = upserted.map { it.sessionId }.toSet() + removed
        val gone = removed.toSet()
        val kept = sessions.filter { it.sessionId !in replaced } + upserted.filter { it.sessionId !in gone }
        return Revised(SessionSet(revision, kept), result)
    }

    /** The session with [sessionId], if the set has it. */
    fun session(sessionId: String): AgentSession? = sessions.firstOrNull { it.sessionId == sessionId }

    override fun equals(other: Any?): Boolean =
        other is SessionSet && revision == other.revision && sessions == other.sessions

    override fun hashCode(): Int = revision.hashCode() * 31 + sessions.hashCode()

    override fun toString(): String = "SessionSet(revision=$revision, sessions=$sessions)"

    private companion object {
        fun sorted(sessions: List<AgentSession>): List<AgentSession> =
            sessions.sortedWith(
                compareByDescending<AgentSession> { it.lastActivityMs ?: Long.MIN_VALUE }.thenBy { it.sessionId },
            )
    }
}
