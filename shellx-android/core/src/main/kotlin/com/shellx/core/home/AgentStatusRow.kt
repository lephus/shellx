package com.shellx.core.home

import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.link.core.AgentState
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

/**
 * One session as a line of status: where it runs, its state, and how long that state has lasted. [online] is whether
 * the session's Mac is online (an offline Mac's sessions are its last known ones). [elapsed] is now minus
 * `stateSinceMs`, never negative (the Mac's clock may run ahead of the phone's); null when the Mac did not say when the
 * state began. The Mac's name never prints.
 */
data class AgentStatusRow(
    val ref: SessionRef,
    val machineName: String,
    val state: AgentState,
    val online: Boolean,
    val elapsed: Duration?,
) {
    val id: SessionRef get() = ref

    override fun toString(): String =
        "AgentStatusRow(ref=$ref, machineName=<redacted>, state=${state.wire}, online=$online, elapsed=$elapsed)"

    companion object {
        fun of(session: MachineSession, nowMs: Long): AgentStatusRow = AgentStatusRow(
            ref = session.ref,
            machineName = session.machineName,
            state = session.session.state,
            online = session.online,
            elapsed = session.session.stateSinceMs?.let { since -> maxOf(0, nowMs - since).milliseconds },
        )

        /** The rows for [sessions]: needs you first, then running, then done (idle), then any state this app does
         *  not know; within each, the most recently active first. */
        fun rows(sessions: List<MachineSession>, nowMs: Long): List<AgentStatusRow> = sessions
            .sortedWith(
                compareBy<MachineSession> { rank(it.session.state) }
                    .thenByDescending { it.session.lastActivityMs ?: Long.MIN_VALUE }
                    .thenBy { it.machineId }
                    .thenBy { it.session.sessionId },
            )
            .map { of(it, nowMs) }

        private fun rank(state: AgentState): Int = when (state) {
            AgentState.NEEDS_INPUT -> 0
            AgentState.WORKING -> 1
            AgentState.IDLE -> 2
            else -> 3
        }
    }
}
