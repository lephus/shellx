package com.shellx.core.link

import com.shellx.link.core.AgentSession

/** An agent session with the Mac it runs on. [online] is whether the Mac is online now: an offline Mac's sessions
 *  are its last known ones. The Mac's name never prints. */
data class MachineSession(val machineId: String, val machineName: String, val online: Boolean, val session: AgentSession) {
    val ref: SessionRef get() = SessionRef(machineId, session.sessionId, session.agent, session.workspaceTitle)

    val id: SessionRef get() = ref

    override fun toString(): String =
        "MachineSession(machineId=$machineId, machineName=<redacted>, online=$online, session=$session)"
}
