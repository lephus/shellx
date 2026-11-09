package com.shellx.app.ui.workspaces

import com.shellx.app.ui.home.FocusKind
import com.shellx.core.home.GoneRemovals
import com.shellx.core.home.HomeFocus
import com.shellx.core.link.HubState
import com.shellx.core.link.MachineSession
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState

/** The agents outside workspaces of one Mac (`OtherSessionsView.swift`'s `sessions` and `kind`). */
object OtherSessionsModel {
    /** The sessions the page lists: none that [removed] hides. */
    fun sessions(hub: HubState, machineId: String, removed: GoneRemovals): List<MachineSession> =
        removed.shown(hub.otherSessions(machineId))

    /** The group a session is drawn in: by its state; a finished one as "done" for `HomeFocus.JUST_DONE_FOR` after it
     *  finished (a finish newer than the clock counts as now), then as idle. An ended one, or a state this app does not
     *  know, is "ended". */
    fun kind(session: AgentSession, finishedAtMs: Long?, nowMs: Long): FocusKind = when (session.state) {
        AgentState.NEEDS_INPUT -> FocusKind.NEEDS_YOU
        AgentState.WORKING -> FocusKind.RUNNING
        AgentState.IDLE ->
            if (finishedAtMs != null && maxOf(0, nowMs - finishedAtMs) < HomeFocus.JUST_DONE_FOR.inWholeMilliseconds) {
                FocusKind.JUST_DONE
            } else {
                FocusKind.IDLE
            }
        else -> FocusKind.ENDED
    }
}
