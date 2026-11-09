package com.shellx.app.ui.agent

import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind

/** The fixtures of `AgentRenderTests.swift`. */
object AgentFixtures {
    const val NOW_MS: Long = 1_700_000_000_000

    val session: MachineSession = MachineSession(
        "m1", "MacBook Pro", true,
        AgentSession(
            "s1", "claude", "ws-shellx", "shellx", state = AgentState.WORKING, stateSinceMs = NOW_MS - 240_000,
            lastActivityMs = NOW_MS - 5_000,
        ),
    )

    val ref: SessionRef get() = session.ref

    fun entry(seq: Int, role: ChatEntryRole, kind: ChatEntryKind, text: String, tool: String? = null, truncated: Boolean? = null): ChatEntry =
        ChatEntry("e$seq", 1, seq.toLong(), role, kind, text, truncated, tool, NOW_MS - (20 - seq) * 30_000L)

    val everyKind: List<ChatEntry> = listOf(
        entry(1, ChatEntryRole.USER, ChatEntryKind.PROSE, "Sửa giúp mình lỗi build ở shellx nhé."),
        entry(2, ChatEntryRole.AGENT, ChatEntryKind.THOUGHT, "Lỗi nằm ở bước link; xem log trước đã. Có thể thiếu import ShellXAppCore."),
        entry(3, ChatEntryRole.AGENT, ChatEntryKind.TOOL_USE, "swift build --package-path shellx-ios/Packages/ShellXAppCore", tool = "Bash"),
        entry(4, ChatEntryRole.SYSTEM, ChatEntryKind.STATUS, "Đã nén ngữ cảnh."),
        entry(
            5, ChatEntryRole.AGENT, ChatEntryKind.PROSE,
            "Mình đã sửa **import thiếu** trong `HomeView.swift`:\n\n- thêm `import ShellXAppCore`\n- chạy lại `swift test`\n\nBuild xanh rồi.",
        ),
        entry(6, ChatEntryRole.AGENT, ChatEntryKind("attachment"), "image.png (240 KB)"),
        entry(7, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "Log rất dài… ".repeat(60), truncated = true),
    )

    val pending: MachinePendingItem = MachinePendingItem(
        "m1", "MacBook Pro",
        PendingItem(
            requestId = "p1", kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-shellx", workspaceTitle = "shellx",
            toolName = "Bash", toolInputPreview = """{"command":"git push origin feat/agent"}""", createdAtMs = 1,
            modes = listOf("once", "always", "deny"),
        ),
        true,
    )

    /** `testLongCodeBlockWraps`' entry: about 4 KB, a fenced block with a 600-character line and many short ones. */
    val longLine: String = "x".repeat(600)
    val codeLines: List<String> = (1..60).map { "let value$it = compute($it) // مرحبا 🚀" }
    val code: String = "Kết quả:\n\n```swift\n$longLine\n${codeLines.joinToString("\n")}\n```\n\nXong."
}
