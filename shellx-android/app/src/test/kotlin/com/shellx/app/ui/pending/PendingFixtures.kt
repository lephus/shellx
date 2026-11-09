package com.shellx.app.ui.pending

import com.shellx.core.link.MachinePendingItem
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import com.shellx.link.core.PendingQuestion
import com.shellx.link.core.PendingQuestionOption

/** The items of `PendingCardRenderTests.swift`, translated literally (`.other("teleport")` is `PendingKind("teleport")`). */
object PendingFixtures {
    fun mac(item: PendingItem, actionable: Boolean = true): MachinePendingItem = MachinePendingItem("m1", "MacBook Pro", item, actionable)

    fun permission(
        preview: String? = """{"command":"git push origin feat/pairing","description":"Push the branch"}""",
        modes: List<String> = listOf("once", "always", "all", "deny"),
        tool: String = "Bash",
        requestId: String = "p1",
        workspaceId: String = "ws",
        workspaceTitle: String = "shellx",
    ): PendingItem = PendingItem(
        requestId = requestId, kind = PendingKind.PERMISSION, agent = "claude", workspaceId = workspaceId,
        workspaceTitle = workspaceTitle, toolName = tool, toolInputPreview = preview, createdAtMs = 1, modes = modes,
    )

    val edit: PendingItem = PendingItem(
        requestId = "e1", kind = PendingKind.PERMISSION, agent = "codex", workspaceId = "ws", workspaceTitle = "web",
        toolName = "Edit",
        toolInputPreview = """{"file_path":"/Users/me/web/app/page.tsx","old_string":"<h1>Hello</h1>","new_string":"<h1>Xin chào</h1>"}""",
        createdAtMs = 2, modes = listOf("always", "deny"),
    )

    val questions: List<PendingQuestion> = listOf(
        PendingQuestion(
            id = "db", header = "Database", prompt = "Which database should the sync service use?", multiSelect = false,
            options = listOf(
                PendingQuestionOption("pg", "Postgres", "Already runs on the VPS"),
                PendingQuestionOption("sq", "SQLite", "One file, no server"),
            ),
        ),
        PendingQuestion(
            id = "checks", prompt = "Which checks run before a push?", multiSelect = true,
            options = listOf(
                PendingQuestionOption("lint", "Lint"),
                PendingQuestionOption("unit", "Unit tests"),
                PendingQuestionOption("ui", "UI tests", "About 5 minutes"),
            ),
        ),
    )

    fun question(requestId: String = "q1", workspaceId: String = "ws"): PendingItem = PendingItem(
        requestId = requestId, kind = PendingKind.QUESTION, agent = "claude", workspaceId = workspaceId, workspaceTitle = "shellx",
        createdAtMs = 3, questions = questions,
    )

    val planText: String = """
        ## Pair Macs by QR

        1. Add `PairingModel` and its **tests** first.
        2. Build the pairing sheet: scan, paste, confirm.
        3. "Your Macs" with unpair.

        ### Checks
        - `swift test` for ShellXAppCore
          - render tests in light and dark
        ```
        dev.sh test all
        ```
    """.trimIndent()

    fun plan(text: String? = planText, modes: List<String> = listOf("manual", "auto_accept", "ultraplan", "deny")): PendingItem =
        PendingItem(
            requestId = "x1", kind = PendingKind.EXIT_PLAN, agent = "claude", workspaceId = "ws", workspaceTitle = "shellx",
            createdAtMs = 4, modes = modes, planPreview = text,
        )

    val unknown: PendingItem = PendingItem(
        requestId = "u1", kind = PendingKind("teleport"), agent = "claude", workspaceId = "ws", workspaceTitle = "relay",
        createdAtMs = 5, modes = listOf("once"),
    )
}
