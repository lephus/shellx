package com.shellx.app.testing

import com.shellx.app.ui.workspaces.WorkspaceGroup
import com.shellx.core.home.FocusItem
import com.shellx.core.home.HomeFocus
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.workspaces.WorkspaceRef
import com.shellx.core.workspaces.WorkspaceRow
import com.shellx.core.workspaces.WorkspaceState
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import java.time.LocalDateTime
import java.time.ZoneId

/** The fixtures of `WorkspaceListRenderTests.swift`: mockup A's agents, the workspaces of two Macs, two requests. */
object HomeFixtures {
    const val NOW_MS: Long = 1_700_000_000_000

    fun ref(id: String, machine: String = "m1"): WorkspaceRef = WorkspaceRef(machine, id)

    /** Epoch ms [minutesAgo] minutes before [NOW_MS]. */
    fun ms(minutesAgo: Double): Long = (NOW_MS - minutesAgo * 60_000).toLong()

    fun session(
        id: String,
        title: String,
        state: AgentState,
        minutesAgo: Double,
        workspace: String = "shellx",
        agent: String = "claude",
        machine: String = "m1",
        machineName: String = "MacBook Pro",
        online: Boolean = true,
    ): MachineSession = MachineSession(
        machineId = machine,
        machineName = machineName,
        online = online,
        session = AgentSession(
            sessionId = id, agent = agent, workspaceId = "ws-$workspace", workspaceTitle = workspace, title = title,
            state = state, stateSinceMs = ms(minutesAgo), lastActivityMs = ms(minutesAgo),
        ),
    )

    fun item(session: MachineSession, question: String? = null, finishedAtMs: Long? = null): FocusItem =
        FocusItem(session, session.session.title ?: "", question, finishedAtMs)

    val shellx = WorkspaceRow(
        id = ref("ws-shellx"), title = "shellx-ios", directory = "~/shellx/shellx-ios", branch = "feat/workspaces",
        state = WorkspaceState.NEEDS_YOU, question = "Cho phép chạy xcodebuild test?",
    )
    val relay = WorkspaceRow(
        id = ref("ws-relay"), title = "relay", directory = "~/shellx/relay", branch = "main", ports = listOf(8787),
        state = WorkspaceState.RUNNING,
    )
    val web = WorkspaceRow(
        id = ref("ws-web"), title = "web", directory = "~/shellx/web", branch = "develop", ports = listOf(3000),
        state = WorkspaceState.DONE,
    )
    val notes = WorkspaceRow(id = ref("ws-notes"), title = "notes", directory = "~", state = WorkspaceState.IDLE)
    val broken = WorkspaceRow(
        id = ref("ws-broken"), title = "a-very-long-workspace-name-that-goes-on-and-on",
        directory = "~/code/a/deeply/nested/directory", branch = "feature/a-long-branch-name",
        ports = listOf(3000, 3001, 5173), state = WorkspaceState.ERROR,
    )

    val macbook = WorkspaceGroup(
        id = "m1", name = "MacBook Pro", state = MachineLinkState.Online, isDefault = true,
        rows = listOf(shellx, relay, web, notes), allowsControl = true, listsWorkspaces = true, otherSessionCount = 0,
    )

    /** 2026-10-28 08:12 in the default zone. */
    val eightTwelve: Long = LocalDateTime.of(2026, 10, 28, 8, 12).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()

    val mini = WorkspaceGroup(
        id = "m2", name = "Mac mini", state = MachineLinkState.Offline(eightTwelve), isDefault = false, rows = emptyList(),
        allowsControl = false, listsWorkspaces = true, otherSessionCount = 0,
    )

    val pending: List<MachinePendingItem> = listOf(
        MachinePendingItem(
            machineId = "m1", machineName = "MacBook Pro",
            item = PendingItem(
                requestId = "p1", kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-shellx",
                workspaceTitle = "shellx-ios", toolName = "Bash", toolInputPreview = """{"command":"xcodebuild test"}""",
                createdAtMs = 1, modes = listOf("once", "always", "deny"),
            ),
            actionable = true,
        ),
        MachinePendingItem(
            machineId = "m1", machineName = "MacBook Pro",
            item = PendingItem(
                requestId = "p2", kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-shellx",
                workspaceTitle = "shellx-ios", toolName = "Bash", toolInputPreview = """{"command":"git push"}""",
                createdAtMs = 2, modes = listOf("once", "always", "deny"),
            ),
            actionable = true,
        ),
    )

    /** The agents of mockup A, as HomeFocus sorts them. */
    val mockup = HomeFocus(
        needsYou = listOf(
            item(session("s1", "Sửa nút ＋ trên iOS", AgentState.NEEDS_INPUT, 2.0), question = "Cho phép chạy xcodebuild?"),
        ),
        running = listOf(
            item(session("s2", "Viết test SessionSet", AgentState.WORKING, 8.0)),
            item(session("s3", "Dọn README", AgentState.WORKING, 1.0, workspace = "toknix", agent = "codex")),
        ),
        justDone = listOf(
            item(session("s4", "Build bản 1.5.1", AgentState.IDLE, 12.0), finishedAtMs = NOW_MS - 12 * 60_000),
        ),
        ended = listOf(
            item(session("s5", "Đổi tên nhánh", AgentState.ENDED, 30.0)),
            item(session("s6", "Sửa lỗi relay", AgentState.ENDED, 95.0, workspace = "relay")),
            item(session("s7", "Viết spec", AgentState.ENDED, 240.0, agent = "codex")),
        ),
    )
}
