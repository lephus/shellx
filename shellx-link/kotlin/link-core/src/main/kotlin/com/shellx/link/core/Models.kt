package com.shellx.link.core

/** One agent request waiting for a human decision: a permission prompt, a question or a plan exit. */
data class PendingItem(
    val requestId: String,
    val kind: PendingKind,
    /** Agent name, for example `claude`. */
    val agent: String,
    val workspaceId: String,
    val workspaceTitle: String,
    val toolName: String? = null,
    val toolInputPreview: String? = null,
    val createdAtMs: Long,
    /** The answers this request accepts, as wire strings (`PermissionMode` or `ExitPlanMode` values). */
    val modes: List<String> = emptyList(),
    val questions: List<PendingQuestion>? = null,
    /** The plan text of an `exit_plan` request. */
    val planPreview: String? = null,
) {
    companion object {
        /** Maximum UTF-8 bytes of `toolInputPreview` and of `planPreview` on the wire. */
        const val MAX_PREVIEW_BYTES = 8192
    }
}

/** One question of a `question` request. */
data class PendingQuestion(
    val id: String,
    val header: String? = null,
    val prompt: String,
    val multiSelect: Boolean,
    val options: List<PendingQuestionOption>,
)

/** One option of a [PendingQuestion]. A [LinkDecision.Question] selects options by `label`. */
data class PendingQuestionOption(val id: String, val label: String, val description: String? = null)

/** The user's decision in an `agent.reply` (PROTOCOL.md section 4, "Decision"). */
sealed interface LinkDecision {
    /** The wire `kind`: `permission`, `question`, `exit_plan`, or the kind this version does not know. */
    val kind: String

    data class Permission(val mode: PermissionMode) : LinkDecision {
        override val kind: String get() = "permission"
    }

    /** Positional answers: `selections[i]` answers `questions[i]`. */
    data class Question(val selections: List<String>) : LinkDecision {
        override val kind: String get() = "question"
    }

    /** A non-empty `feedback` rejects the plan and asks the agent to revise it, whatever the mode. */
    data class ExitPlan(val mode: ExitPlanMode, val feedback: String? = null) : LinkDecision {
        override val kind: String get() = "exit_plan"
    }

    /** A `kind` this version does not know. */
    data class Other(override val kind: String) : LinkDecision
}

/** One agent session running on the host, as listed by `agent.sessions`. */
data class AgentSession(
    val sessionId: String,
    val agent: String,
    val workspaceId: String,
    val workspaceTitle: String,
    val title: String? = null,
    val state: AgentState,
    /** Unix time in milliseconds at which `state` began. */
    val stateSinceMs: Long? = null,
    val lastActivityMs: Long? = null,
)

/** One entry of a session's chat transcript. Entries are upserted by `id`; `seq` orders them. */
data class ChatEntry(
    val id: String,
    /** Revision of this entry; strictly greater in every later emission of the same `id`. */
    val rev: Long,
    val seq: Long,
    val role: ChatEntryRole,
    val kind: ChatEntryKind,
    val text: String,
    /** True when the host cut `text`; null when it did not. */
    val truncated: Boolean? = null,
    val toolName: String? = null,
    val tsMs: Long,
) {
    companion object {
        /** Maximum UTF-8 bytes of `text` on the wire. */
        const val MAX_TEXT_BYTES = 4096

        /** Of two emissions of one entry, the one with the higher `rev`; `a` when equal. */
        fun newer(a: ChatEntry, b: ChatEntry): ChatEntry = if (b.rev > a.rev) b else a
    }
}

/** One workspace of the Mac, as listed by `workspace.list`. */
data class LinkWorkspace(
    val workspaceId: String,
    val title: String,
    /** Position in the Mac's sidebar. */
    val order: Int,
    /** Display text for the working directory, with the home directory written `~`. */
    val directory: String? = null,
    val branch: String? = null,
    /** Listening ports, when the workspace has any. */
    val ports: List<Int>? = null,
    val terminals: List<LinkTerminal>,
)

/** One terminal of a workspace, as listed in `workspace.list`. */
data class LinkTerminal(
    val terminalId: String,
    val title: String,
    /** Position among the workspace's terminals. */
    val order: Int,
    /** Whether the terminal is the selected one on the Mac. */
    val selected: Boolean,
    /** The agent session running in this terminal, when there is one. */
    val sessionId: String? = null,
)
