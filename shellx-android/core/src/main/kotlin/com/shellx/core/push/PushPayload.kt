package com.shellx.core.push

/** What an FCM data message from a paired Mac says (contracts §8). The workspace title never prints. */
sealed interface PushPayload {
    val machineId: String
    val requestId: String

    /** An agent waits for the user on [machineId]; tapping the notification opens the waiting requests. */
    data class NeedsYou(
        override val machineId: String,
        override val requestId: String,
        val agent: String,
        val workspaceTitle: String,
    ) : PushPayload {
        /** Contracts §8: use `push_needs_you_workspace` when true, else `push_needs_you`. */
        val showsWorkspace: Boolean get() = workspaceTitle.trim().isNotEmpty()

        override fun toString(): String =
            "NeedsYou(machineId=$machineId, requestId=$requestId, agent=$agent, workspaceTitle=<redacted>)"
    }

    /** The request was handled: its notification, if still shown, goes away. */
    data class Resolved(override val machineId: String, override val requestId: String) : PushPayload

    companion object {
        /**
         * Null unless `kind` is "needs_you" or "resolved" and `machine_id` and `request_id` are non-empty. A needs_you
         * also needs a non-empty `agent`. A missing `workspace_title` is "". Every other key (`google.*`, `from`, …) is
         * ignored.
         */
        fun parse(data: Map<String, String>): PushPayload? {
            val machineId = data["machine_id"]?.takeIf { it.isNotEmpty() } ?: return null
            val requestId = data["request_id"]?.takeIf { it.isNotEmpty() } ?: return null
            return when (data["kind"]) {
                "needs_you" -> {
                    val agent = data["agent"]?.takeIf { it.isNotEmpty() } ?: return null
                    NeedsYou(machineId, requestId, agent, data["workspace_title"] ?: "")
                }
                "resolved" -> Resolved(machineId, requestId)
                else -> null
            }
        }
    }
}
