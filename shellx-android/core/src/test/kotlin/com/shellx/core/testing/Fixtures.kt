package com.shellx.core.testing

import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import com.shellx.link.core.PendingQuestion
import com.shellx.link.core.PendingQuestionOption

// The fixtures of AsyncTestSupport.swift and PendingRig.swift, with their values.

fun pendingItem(id: String, createdAtMs: Long = 1_700_000_000_000, workspace: String = "shellx"): PendingItem =
    PendingItem(
        requestId = id, kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-$workspace",
        workspaceTitle = workspace, toolName = "Bash", toolInputPreview = "ls", createdAtMs = createdAtMs,
        modes = listOf("once", "deny"),
    )

fun agentSession(
    id: String,
    state: AgentState = AgentState.WORKING,
    lastActivityMs: Long? = 1_700_000_000_000,
    stateSinceMs: Long? = 1_700_000_000_000,
    workspace: String = "shellx",
): AgentSession = AgentSession(
    sessionId = id, agent = "claude", workspaceId = "ws-$workspace", workspaceTitle = workspace, state = state,
    stateSinceMs = stateSinceMs, lastActivityMs = lastActivityMs,
)

fun linkTerminal(id: String, sessionId: String? = null, order: Int = 0, selected: Boolean = false): LinkTerminal =
    LinkTerminal(terminalId = id, title = "zsh $id", order = order, selected = selected, sessionId = sessionId)

/** A workspace with the id `ws-<workspace>`, the one [agentSession] and [pendingItem] name. */
fun linkWorkspace(
    workspace: String = "shellx",
    order: Int = 0,
    terminals: List<LinkTerminal> = emptyList(),
    directory: String? = null,
    branch: String? = null,
    ports: List<Int>? = null,
): LinkWorkspace = LinkWorkspace(
    workspaceId = "ws-$workspace", title = workspace, order = order, directory = directory, branch = branch,
    ports = ports, terminals = terminals,
)

fun chatEntry(seq: Long, text: String? = null): ChatEntry = ChatEntry(
    id = "e-$seq", rev = 1, seq = seq, role = ChatEntryRole.AGENT, kind = ChatEntryKind.PROSE,
    text = text ?: "entry $seq", tsMs = 1_700_000_000_000 + seq,
)

fun permissionItem(id: String, modes: List<String> = listOf("once", "always", "deny")): PendingItem = PendingItem(
    requestId = id, kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-shellx",
    workspaceTitle = "shellx", toolName = "Bash", toolInputPreview = """{"command":"git push"}""",
    createdAtMs = 1_700_000_000_000, modes = modes,
)

fun questionItem(id: String): PendingItem = PendingItem(
    requestId = id, kind = PendingKind.QUESTION, agent = "claude", workspaceId = "ws-shellx",
    workspaceTitle = "shellx", createdAtMs = 1_700_000_000_001, modes = emptyList(),
    questions = listOf(
        PendingQuestion(
            id = "q1", prompt = "Which database?", multiSelect = false,
            options = listOf(PendingQuestionOption("pg", "Postgres"), PendingQuestionOption("sq", "SQLite")),
        ),
    ),
)

fun planItem(id: String): PendingItem = PendingItem(
    requestId = id, kind = PendingKind.EXIT_PLAN, agent = "claude", workspaceId = "ws-shellx",
    workspaceTitle = "shellx", createdAtMs = 1_700_000_000_002, modes = listOf("auto_accept", "manual", "deny"),
    planPreview = "1. Add tests.\n2. Ship.",
)
