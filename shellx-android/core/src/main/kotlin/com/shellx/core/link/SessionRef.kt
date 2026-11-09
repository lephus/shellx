package com.shellx.core.link

/**
 * Points at one agent session on one Mac.
 *
 * Identity is [machineId] and [sessionId]: two refs to the same session are equal even when one carries an older
 * [workspaceTitle]. [agent] and [workspaceTitle] are only labels for display. The title never prints.
 */
data class SessionRef(val machineId: String, val sessionId: String, val agent: String, val workspaceTitle: String) {
    override fun equals(other: Any?): Boolean =
        other is SessionRef && machineId == other.machineId && sessionId == other.sessionId

    override fun hashCode(): Int = machineId.hashCode() * 31 + sessionId.hashCode()

    override fun toString(): String =
        "SessionRef(machineId=$machineId, sessionId=$sessionId, agent=$agent, workspaceTitle=<redacted>)"
}
