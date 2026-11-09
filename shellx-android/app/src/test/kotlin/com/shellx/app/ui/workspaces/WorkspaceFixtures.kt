package com.shellx.app.ui.workspaces

import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.workspaces.WorkspacePane
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind

/** The fixtures of `WorkspaceRenderTests.swift`. */
object WorkspaceFixtures {
    const val NOW_MS: Long = 1_700_000_000_000

    fun session(id: String, state: AgentState, since: Long = 240_000): MachineSession = MachineSession(
        "m1", "MacBook Pro", true,
        AgentSession(id, "claude", "ws-shellx", "shellx-ios", state = state, stateSinceMs = NOW_MS - since, lastActivityMs = NOW_MS - 5_000),
    )

    val claude: MachineSession = session("s-claude", AgentState.NEEDS_INPUT)
    val dev: MachineSession = session("s-dev", AgentState.WORKING)

    /** `claude` (an agent that asks), `zsh` (a shell), `dev :3000` (an agent at work). */
    val panes: List<WorkspacePane> = listOf(
        WorkspacePane("t-claude", "claude", claude),
        WorkspacePane("t-zsh", "zsh"),
        WorkspacePane("t-dev", "dev :3000", dev),
    )

    val workspace: LinkWorkspace = LinkWorkspace(
        "ws-shellx", "shellx-ios", 0, directory = "~/shellx/shellx-ios", branch = "feat/workspaces",
        terminals = listOf(
            LinkTerminal("t-claude", "claude", 0, selected = false, sessionId = "s-claude"),
            LinkTerminal("t-zsh", "zsh", 1, selected = true),
            LinkTerminal("t-dev", "dev :3000", 2, selected = false, sessionId = "s-dev"),
        ),
    )

    val request: MachinePendingItem = MachinePendingItem(
        "m1", "MacBook Pro",
        PendingItem(
            requestId = "p1", kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-shellx", workspaceTitle = "shellx-ios",
            toolName = "Bash", toolInputPreview = """{"command":"xcodebuild test"}""", createdAtMs = 1, modes = listOf("once", "always", "deny"),
        ),
        true,
    )

    private fun entry(seq: Int, role: ChatEntryRole, kind: ChatEntryKind, text: String, tool: String? = null): ChatEntry =
        ChatEntry("e$seq", 1, seq.toLong(), role, kind, text, toolName = tool, tsMs = NOW_MS - (10 - seq) * 30_000L)

    val chat: List<ChatEntry> = listOf(
        entry(1, ChatEntryRole.USER, ChatEntryKind.PROSE, "thêm danh sách workspace vào màn chính"),
        entry(2, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "Mình sẽ thêm **WorkspaceList** và sửa màn chính. Cần chạy test để kiểm tra."),
        entry(3, ChatEntryRole.AGENT, ChatEntryKind.TOOL_USE, "ShellX/UI/Home/HomeView.swift", "Edit"),
        entry(4, ChatEntryRole.AGENT, ChatEntryKind.TOOL_USE, "ShellX/UI/Workspace/WorkspaceList.swift", "Edit"),
        entry(5, ChatEntryRole.AGENT, ChatEntryKind.TOOL_USE, "xcodebuild test", "Bash"),
    )
}
