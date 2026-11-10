package com.shellx.app.ui.nav

import android.net.Uri
import com.shellx.core.link.HubState
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef

/** The three work routes (contracts §20), in exactly plan 3E Task 12's shape (3E keeps this file). */
object WorkRoutes {
    const val WORKSPACE = "workspace/{machineId}/{workspaceId}"
    const val AGENT = "agent/{machineId}/{sessionId}"

    /** Both arguments nullable, default null: plain `pending` lists every waiting request. */
    const val PENDING = "pending?machineId={machineId}&workspaceId={workspaceId}"

    fun workspace(ref: WorkspaceRef): String = "workspace/${Uri.encode(ref.machineId)}/${Uri.encode(ref.workspaceId)}"

    fun agent(ref: SessionRef): String = "agent/${Uri.encode(ref.machineId)}/${Uri.encode(ref.sessionId)}"

    fun pending(): String = "pending"

    fun pendingIn(machineId: String, workspaceId: String): String =
        "pending?machineId=${Uri.encode(machineId)}&workspaceId=${Uri.encode(workspaceId)}"

    /** The agent route's ref from the hub's session sets; agent and workspaceTitle "" when the hub lists none
     *  (SessionRef's identity is the two ids). */
    fun sessionRef(hub: HubState, machineId: String, sessionId: String): SessionRef {
        val session = hub.machine(machineId)?.sessions?.sessions?.firstOrNull { it.sessionId == sessionId }
            ?: return SessionRef(machineId, sessionId, "", "")
        return SessionRef(machineId, sessionId, session.agent, session.workspaceTitle)
    }
}
