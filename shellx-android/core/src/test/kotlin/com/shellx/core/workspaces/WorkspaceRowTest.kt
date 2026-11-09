package com.shellx.core.workspaces

import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.WorkspaceSet
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.linkTerminal
import com.shellx.core.testing.linkWorkspace
import com.shellx.core.testing.pendingItem
import com.shellx.core.text.graphemeCount
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkWorkspace
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import com.shellx.link.core.PendingQuestion
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The state and the one-line question of a workspace row, derived from the Mac's lists. */
class WorkspaceRowTest {
    private val machine = "mac-1"

    private fun rows(
        workspaces: List<LinkWorkspace>,
        sessions: List<AgentSession> = emptyList(),
        pending: List<MachinePendingItem> = emptyList(),
        finished: Set<String> = emptySet(),
    ): List<WorkspaceRow> = WorkspaceRow.rows(WorkspaceSet(1, workspaces), sessions, pending, finished, machine)

    private fun pending(
        id: String,
        workspace: String = "shellx",
        machineId: String? = null,
        item: PendingItem? = null,
    ): MachinePendingItem = MachinePendingItem(machineId ?: machine, "Mac", item ?: pendingItem(id, workspace = workspace), true)

    private fun questionItem(id: String, prompts: List<String>, workspace: String = "shellx"): PendingItem = PendingItem(
        requestId = id, kind = PendingKind.QUESTION, agent = "claude", workspaceId = "ws-$workspace",
        workspaceTitle = workspace, createdAtMs = 1_700_000_000_000, modes = emptyList(),
        questions = prompts.mapIndexed { index, prompt ->
            PendingQuestion(id = "q$index", header = "H", prompt = prompt, multiSelect = false, options = emptyList())
        },
    )

    @Test fun needsYouWinsOverRunning() {
        val result = rows(
            listOf(linkWorkspace("shellx")), sessions = listOf(agentSession("s1", state = AgentState.WORKING)),
            pending = listOf(pending("r1")), finished = setOf("s1"),
        )

        assertEquals(listOf(WorkspaceState.NEEDS_YOU), result.map { it.state })
    }

    @Test fun runningWinsOverDone() {
        val result = rows(
            listOf(linkWorkspace("shellx")),
            sessions = listOf(agentSession("s1", state = AgentState.WORKING), agentSession("s2", state = AgentState.IDLE)),
            finished = setOf("s2"),
        )

        assertEquals(listOf(WorkspaceState.RUNNING), result.map { it.state })
    }

    @Test fun questionFromFirstPending() {
        val first = pending("r1", item = questionItem("r1", listOf("Nút chính nên dùng màu nào?", "Chạy test nào?")))
        val second = pending("r2")
        val elsewhere = pending("r3", workspace = "web", item = questionItem("r3", listOf("Không phải của shellx"), workspace = "web"))
        val otherMac = pending("r4", machineId = "mac-2", item = questionItem("r4", listOf("Mac khác")))

        val result = rows(
            listOf(linkWorkspace("shellx"), linkWorkspace("web", order = 1)),
            pending = listOf(otherMac, first, second, elsewhere),
        )

        assertEquals(listOf(WorkspaceState.NEEDS_YOU, WorkspaceState.NEEDS_YOU), result.map { it.state })
        // The first pending of the workspace, on this Mac, and its first line.
        assertEquals("Nút chính nên dùng màu nào?", result[0].question)
        assertEquals("Không phải của shellx", result[1].question)
    }

    @Test fun questionOfPermissionIsItsTellingValue() {
        val permission = pending(
            "r1",
            item = PendingItem(
                requestId = "r1", kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-shellx",
                workspaceTitle = "shellx", toolName = "Bash",
                toolInputPreview = """{"command":"git push origin main","description":"Push"}""", createdAtMs = 1,
                modes = listOf("once", "deny"),
            ),
        )

        assertEquals("git push origin main", rows(listOf(linkWorkspace("shellx")), pending = listOf(permission))[0].question)
    }

    @Test fun questionIsOneShortLine() {
        val long = "x".repeat(500)
        val plan = pending(
            "r1",
            item = PendingItem(
                requestId = "r1", kind = PendingKind.EXIT_PLAN, agent = "claude", workspaceId = "ws-shellx",
                workspaceTitle = "shellx", createdAtMs = 1, modes = listOf("manual", "deny"),
                planPreview = "\n  ## Ghép cặp Mac  \n\n1. Làm test",
            ),
        )
        assertEquals("## Ghép cặp Mac", rows(listOf(linkWorkspace("shellx")), pending = listOf(plan))[0].question)

        val cut = rows(listOf(linkWorkspace("shellx")), pending = listOf(pending("r2", item = questionItem("r2", listOf(long)))))[0]
        assertEquals(WorkspaceRow.QUESTION_LENGTH, cut.question?.graphemeCount())
        assertTrue(cut.question?.endsWith("…") ?: false)
    }

    @Test fun doneFromFinishedSession() {
        val result = rows(
            listOf(linkWorkspace("shellx"), linkWorkspace("web", order = 1)),
            sessions = listOf(agentSession("s1", state = AgentState.IDLE), agentSession("s2", state = AgentState.IDLE, workspace = "web")),
            finished = setOf("s1"),
        )

        assertEquals(listOf(WorkspaceState.DONE, WorkspaceState.IDLE), result.map { it.state })
        assertNull(result[0].question)
    }

    @Test fun idleWithoutAgent() {
        val result = rows(
            listOf(linkWorkspace("shellx"), linkWorkspace("web", order = 1)),
            sessions = listOf(agentSession("s2", state = AgentState.IDLE, workspace = "web")),
        )

        assertEquals(listOf(WorkspaceState.IDLE, WorkspaceState.IDLE), result.map { it.state })
        assertEquals(listOf(null, null), result.map { it.question })
    }

    @Test fun sessionNamedByATerminalBelongsToItsWorkspace() {
        // A session whose own `workspaceId` is empty is still the terminal's.
        val session = AgentSession(
            sessionId = "s1", agent = "claude", workspaceId = "", workspaceTitle = "", state = AgentState.WORKING,
            stateSinceMs = 1, lastActivityMs = 1,
        )
        val result = rows(listOf(linkWorkspace("shellx", terminals = listOf(linkTerminal("t1", sessionId = "s1")))), sessions = listOf(session))

        assertEquals(listOf(WorkspaceState.RUNNING), result.map { it.state })
    }

    @Test fun rowCarriesTheWorkspaceInItsOrder() {
        val terminals = listOf(linkTerminal("t1", sessionId = "s1"), linkTerminal("t2", order = 1, selected = true))
        val result = rows(
            listOf(
                linkWorkspace("web", order = 1),
                linkWorkspace("shellx", order = 0, terminals = terminals, directory = "~/code/shellx", branch = "main", ports = listOf(3000)),
            ),
        )

        assertEquals(listOf(WorkspaceRef(machine, "ws-shellx"), WorkspaceRef(machine, "ws-web")), result.map { it.id })
        assertEquals("shellx", result[0].title)
        assertEquals("~/code/shellx", result[0].directory)
        assertEquals("main", result[0].branch)
        assertEquals(listOf(3000), result[0].ports)
        assertEquals(terminals, result[0].terminals)
        // No ports on the wire means none.
        assertEquals(emptyList(), result[1].ports)
        assertNull(result[1].directory)
        assertNull(result[1].branch)
    }
}
