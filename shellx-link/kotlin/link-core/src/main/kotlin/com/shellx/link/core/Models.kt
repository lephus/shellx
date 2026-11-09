package com.shellx.link.core

// Global Constraint "Secrets": user content (chat text, previews, answers, plan feedback, titles, directories,
// branches, attachment names, device and machine names, host error text) never appears in toString(). Ids, kinds,
// counts and sizes stay visible.

/** `<redacted>` for content that is present, `null` for content that is absent. */
internal fun redact(value: Any?): String = if (value == null) "null" else "<redacted>"

/** A list of content strings by its size only. */
internal fun redactAll(values: List<*>): String = if (values.isEmpty()) "[]" else "[<redacted> × ${values.size}]"

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
    override fun toString(): String = "PendingItem(requestId=$requestId, kind=$kind, agent=$agent, " +
        "workspaceId=$workspaceId, workspaceTitle=<redacted>, toolName=$toolName, " +
        "toolInputPreview=${redact(toolInputPreview)}, createdAtMs=$createdAtMs, modes=$modes, questions=$questions, " +
        "planPreview=${redact(planPreview)})"

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
) {
    override fun toString(): String =
        "PendingQuestion(id=$id, header=${redact(header)}, prompt=<redacted>, multiSelect=$multiSelect, options=$options)"
}

/** One option of a [PendingQuestion]. A [LinkDecision.Question] selects options by `label`. */
data class PendingQuestionOption(val id: String, val label: String, val description: String? = null) {
    override fun toString(): String = "PendingQuestionOption(id=$id, label=<redacted>, description=${redact(description)})"
}

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

        override fun toString(): String = "Question(selections=${redactAll(selections)})"
    }

    /** A non-empty `feedback` rejects the plan and asks the agent to revise it, whatever the mode. */
    data class ExitPlan(val mode: ExitPlanMode, val feedback: String? = null) : LinkDecision {
        override val kind: String get() = "exit_plan"

        override fun toString(): String = "ExitPlan(mode=$mode, feedback=${redact(feedback)})"
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
) {
    override fun toString(): String = "AgentSession(sessionId=$sessionId, agent=$agent, workspaceId=$workspaceId, " +
        "workspaceTitle=<redacted>, title=${redact(title)}, state=$state, stateSinceMs=$stateSinceMs, " +
        "lastActivityMs=$lastActivityMs)"
}

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
    override fun toString(): String = "ChatEntry(id=$id, rev=$rev, seq=$seq, role=$role, kind=$kind, text=<redacted>, " +
        "truncated=$truncated, toolName=$toolName, tsMs=$tsMs)"

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
) {
    override fun toString(): String = "LinkWorkspace(workspaceId=$workspaceId, title=<redacted>, order=$order, " +
        "directory=${redact(directory)}, branch=${redact(branch)}, ports=$ports, terminals=$terminals)"
}

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
) {
    override fun toString(): String =
        "LinkTerminal(terminalId=$terminalId, title=<redacted>, order=$order, selected=$selected, sessionId=$sessionId)"
}
