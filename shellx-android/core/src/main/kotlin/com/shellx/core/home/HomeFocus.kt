package com.shellx.core.home

import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.pending.previewText
import com.shellx.core.workspaces.WorkspaceRow
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import java.time.ZoneId
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/** One session on the home, with what its row shows beyond the session itself. The name and question never print. */
data class FocusItem(
    val session: MachineSession,
    /** From SessionName.distinct over the list the item is in. */
    val name: String,
    /** The first line of the matched request (needs-you items only). */
    val question: String? = null,
    /** When the phone saw the session finish, epoch ms (just-finished items only). */
    val finishedAtMs: Long? = null,
) {
    val id: SessionRef get() = session.ref

    override fun toString(): String = "FocusItem(session=$session, name=<redacted>, " +
        "question=${if (question == null) "null" else "<redacted>"}, finishedAtMs=$finishedAtMs)"
}

/** Which group of the home each session goes in: needs you, running, just finished, and the ended fold. */
data class HomeFocus(
    val needsYou: List<FocusItem>,
    val running: List<FocusItem>,
    val justDone: List<FocusItem>,
    /** Newest end first. */
    val ended: List<FocusItem>,
) {
    /** Nothing needs you, nothing runs and nothing just finished. */
    val isQuiet: Boolean get() = needsYou.isEmpty() && running.isEmpty() && justDone.isEmpty()

    companion object {
        /** How long a finished session stays in "just finished", counted from when the phone saw it finish. */
        val JUST_DONE_FOR: Duration = 3_600.seconds

        /** How long an ended session stays in the Ended fold, counted from its end. */
        val ENDED_FOR: Duration = 43_200.seconds

        val EMPTY: HomeFocus = HomeFocus(emptyList(), emptyList(), emptyList(), emptyList())

        /**
         * Sorts [sessions], first match wins per session:
         * - needs you: every NEEDS_INPUT session; plus, for each request in [pending] that no NEEDS_INPUT session of
         *   its Mac, workspace and agent matches, the most recently active matching session that is not ENDED. A
         *   request matching nothing adds nothing. The question of a card is that of the first request in [pending]
         *   matching it; a request goes to the most recently active matching card;
         * - running: WORKING;
         * - just finished: IDLE and in [finished] (per Mac, by session id, epoch ms) for less than [JUST_DONE_FOR];
         * - ended: ENDED for less than [ENDED_FOR], counted from `stateSinceMs`, else `lastActivityMs` ([endedMs]);
         *   with neither the session is hidden. A negative age (the Mac's clock is ahead) counts as 0. A session in
         *   [dismissed] (the user took it off the list) is left out too.
         *
         * A session [removed] hides (gone from its Mac, removed from this phone) is in no group, counts in none and
         * takes no request: the sorting runs over the others only.
         *
         * The first three lists are newest activity first, then by (machineId, sessionId). Names are distinct across
         * those three together; Ended has its own pass.
         */
        fun make(
            sessions: List<MachineSession>,
            pending: List<MachinePendingItem>,
            finished: Map<String, Map<String, Long>>,
            dismissed: EndedDismissals = EndedDismissals.NONE,
            removed: GoneRemovals = GoneRemovals.NONE,
            nowMs: Long,
            zone: ZoneId = ZoneId.systemDefault(),
        ): HomeFocus {
            val shown = removed.shown(sessions)
            val waiting = shown.filter { it.session.state == AgentState.NEEDS_INPUT }.map { it.ref }.toMutableSet()
            val questions = HashMap<SessionRef, String>()
            for (request in pending) {
                val matching = shown.filter {
                    it.machineId == request.machineId && it.session.workspaceId == request.item.workspaceId &&
                        it.session.agent == request.item.agent
                }
                val target = newest(matching.filter { it.session.state == AgentState.NEEDS_INPUT })
                    ?: newest(matching.filter { it.session.state != AgentState.ENDED })?.also { waiting += it.ref }
                    ?: continue
                if (target.ref !in questions) {
                    request.item.previewText?.let(WorkspaceRow::firstLine)?.let { questions[target.ref] = it }
                }
            }

            val needs = ArrayList<MachineSession>()
            val running = ArrayList<MachineSession>()
            val done = ArrayList<MachineSession>()
            val ended = ArrayList<Pair<MachineSession, Long>>()
            for (machineSession in shown) {
                val session = machineSession.session
                val finishedAt = finished[machineSession.machineId]?.get(session.sessionId)
                val endedAt = endedMs(session)
                when {
                    machineSession.ref in waiting -> needs += machineSession
                    session.state == AgentState.WORKING -> running += machineSession
                    session.state == AgentState.IDLE && finishedAt != null &&
                        maxOf(0, nowMs - finishedAt) < JUST_DONE_FOR.inWholeMilliseconds -> done += machineSession
                    session.state == AgentState.ENDED && endedAt != null -> {
                        if (endedAge(endedAt, nowMs) < ENDED_FOR && !dismissed.hides(machineSession)) {
                            ended += machineSession to endedAt
                        }
                    }
                }
            }

            needs.sortWith(ACTIVITY_FIRST)
            running.sortWith(ACTIVITY_FIRST)
            done.sortWith(ACTIVITY_FIRST)
            ended.sortWith(compareByDescending<Pair<MachineSession, Long>> { it.second }.thenComparator { a, b -> IDENTITY.compare(a.first, b.first) })

            val topNames = SessionName.distinct(needs + running + done, zone)
            val endedSessions = ended.map { it.first }
            val endedNames = SessionName.distinct(endedSessions, zone)
            // Only needs-you sessions ever get a question, so the other lists carry none.
            fun items(list: List<MachineSession>, names: Map<SessionRef, String>): List<FocusItem> =
                list.map { FocusItem(it, names[it.ref] ?: "", question = questions[it.ref]) }
            return HomeFocus(
                needsYou = items(needs, topNames),
                running = items(running, topNames),
                justDone = done.map {
                    FocusItem(it, topNames[it.ref] ?: "", finishedAtMs = finished[it.machineId]?.get(it.session.sessionId))
                },
                ended = items(endedSessions, endedNames),
            )
        }

        /** When the session ended, as the Mac's epoch ms: when it entered its state, else its last activity. Null when
         *  the Mac gave neither; such a session is never on the Ended list. */
        fun endedMs(session: AgentSession): Long? = session.stateSinceMs ?: session.lastActivityMs

        /** How long ago an end at [ms] was. A negative age (the Mac's clock is ahead) counts as 0. */
        internal fun endedAge(ms: Long, nowMs: Long): Duration = maxOf(0, nowMs - ms).milliseconds

        private val IDENTITY: Comparator<MachineSession> =
            compareBy<MachineSession> { it.machineId }.thenBy { it.session.sessionId }

        /** Newest activity first (none counts as the oldest), then by (machineId, sessionId). */
        private val ACTIVITY_FIRST: Comparator<MachineSession> =
            compareByDescending<MachineSession> { it.session.lastActivityMs ?: Long.MIN_VALUE }.then(IDENTITY)

        /** The most recently active of [sessions]; ties go to the lower (machineId, sessionId). */
        private fun newest(sessions: List<MachineSession>): MachineSession? = sessions.minWithOrNull(ACTIVITY_FIRST)
    }
}
