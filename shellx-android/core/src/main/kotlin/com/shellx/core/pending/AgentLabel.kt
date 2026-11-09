package com.shellx.core.pending

/** The name shown for an agent: `claude` is "Claude Code", `codex` is "Codex", any other wire name is shown as it is.
 *  Product names are never translated. */
data class AgentLabel(val text: String) {
    companion object {
        fun of(agent: String): AgentLabel = AgentLabel(
            when (agent) {
                "claude" -> "Claude Code"
                "codex" -> "Codex"
                else -> agent
            },
        )
    }
}
