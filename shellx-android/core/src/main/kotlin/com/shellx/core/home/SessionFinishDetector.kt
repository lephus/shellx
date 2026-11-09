package com.shellx.core.home

import com.shellx.core.link.SessionRef
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState

/**
 * Tells which sessions just finished a turn: working, or waiting on the user, when last seen, and idle now.
 * `MachineHub` runs one over every session list a Mac sends, in memory only: what finished while the app was closed is
 * not reported on the next launch.
 *
 * Each finish, a session's `(sessionId, stateSinceMs)` on one Mac, is reported once: a resync that replays an older
 * list and then the same finish (a reconnect, a restarted Mac app) stays quiet. A session without `stateSinceMs`
 * reports every change to idle, since a replay looks the same.
 *
 * Mutable and not thread-safe: one owner holds it (Conventions, "Value types").
 */
class SessionFinishDetector {
    /** A session's state when last seen. */
    private data class Seen(val state: AgentState, val sinceMs: Long?)

    /** One finish of one session. */
    private data class Finish(val sessionId: String, val sinceMs: Long)

    /** The last list seen from each Mac, by session. */
    private val seen = HashMap<String, Map<String, Seen>>()

    /** The finishes already reported, by Mac. Only sessions the Mac still lists are kept. */
    private val reported = HashMap<String, Set<Finish>>()

    /**
     * Takes the Mac's whole session list; returns the sessions that went from `working` or `needs_input` to `idle`
     * since the last list from that Mac, in list order.
     */
    fun observe(machineId: String, sessions: List<AgentSession>): List<SessionRef> {
        val before = seen[machineId].orEmpty()
        val done = HashSet(reported[machineId].orEmpty())
        val finished = ArrayList<SessionRef>()
        for (session in sessions) {
            if (session.state != AgentState.IDLE) continue
            val previous = before[session.sessionId] ?: continue
            if (previous.state != AgentState.WORKING && previous.state != AgentState.NEEDS_INPUT) continue
            // Without `stateSinceMs` a replay cannot be told from a new turn: every change is one.
            val since = session.stateSinceMs
            if (since != null && !done.add(Finish(session.sessionId, since))) continue
            finished += SessionRef(machineId, session.sessionId, session.agent, session.workspaceTitle)
        }
        val listed = sessions.map { it.sessionId }.toSet()
        reported[machineId] = newest(done.filter { it.sessionId in listed })
        // The last of two entries with one id wins, as Swift's `uniquingKeysWith: { _, last in last }`.
        seen[machineId] = sessions.associate { it.sessionId to Seen(it.state, it.stateSinceMs) }
        return finished
    }

    /** Forgets every Mac not in [machineIds] (unpaired since). */
    fun retain(machineIds: Set<String>) {
        seen.keys.retainAll(machineIds)
        reported.keys.retainAll(machineIds)
    }

    /** A deep copy: what "saved and restored" means in the tests (the iPhone's `Codable` round trip). */
    fun copy(): SessionFinishDetector = SessionFinishDetector().also {
        it.seen.putAll(seen)
        it.reported.putAll(reported)
    }

    /** How many finishes are remembered for [machineId] (tests). */
    internal fun reportedCount(machineId: String): Int = reported[machineId]?.size ?: 0

    companion object {
        /** Finishes remembered per session. */
        const val FINISHES_KEPT = 2

        /** The newest FINISHES_KEPT finishes of each session: a resync replays the current list, so older finishes
         *  cannot come back, and the detector stays small. */
        private fun newest(finishes: List<Finish>): Set<Finish> = finishes.groupBy { it.sessionId }.values
            .flatMap { list -> list.sortedByDescending { it.sinceMs }.take(FINISHES_KEPT) }
            .toSet()
    }
}
