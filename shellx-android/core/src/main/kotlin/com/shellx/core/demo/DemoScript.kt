package com.shellx.core.demo

import com.shellx.core.platform.rethrowIfCancelled
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
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * What the demo's Mac does over time (the iPhone's FakeMacDemoScript, with DemoScript's `start`), so every screen has
 * something to show without an account or a real Mac.
 *
 * [setUp] gives the Mac two Claude Code sessions, both working (and two more outside any terminal, one idle and one
 * ended), each with a chat history that holds every kind of entry (user, agent and system; prose, thought, tool use,
 * status; one cut short), and three workspaces ([WORKSPACES]) that hold them. Then every [INTERVAL], [step] adds a
 * pending request, in turn a permission, a question and a plan, and switches one session between working and idle. At
 * most [MAX_PENDING] requests wait at once: the oldest is resolved when another comes.
 *
 * Main-confined: [run] runs in the scope [start] is given. The data strings are the iPhone demo's, verbatim.
 */
class DemoScript(val mac: FakeMac, private val nowMs: () -> Long) {
    private val waiting = ArrayList<String>()
    private val sessions = ArrayList<AgentSession>()
    private var started: Job? = null

    /**
     * [setUp] (unless [setUp] is false: already done), then a [step] after every [INTERVAL], until cancelled. Steps are
     * numbered from [from]: after steps already played by hand, go on from the next one, so new chat entries never
     * reuse an earlier step's id and seq.
     */
    suspend fun run(sleep: suspend (Duration) -> Unit, setUp: Boolean = true, from: Int = 0) {
        if (setUp) setUp()
        var index = from
        while (true) {
            try {
                sleep(INTERVAL)
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                return
            }
            step(index)
            index += 1
        }
    }

    /**
     * Once: sets the Mac up (sessions and chat are there before the app connects) with one request of each kind
     * already waiting (steps 0, 1 and 2), then keeps playing in [scope] from step 3. A second call returns the same
     * job. Cancel the job to stop.
     */
    fun start(scope: CoroutineScope, sleep: suspend (Duration) -> Unit = { delay(it) }): Job {
        started?.let { return it }
        setUp()
        for (index in 0 until PLAYED) step(index)
        return scope.launch { run(sleep, setUp = false, from = PLAYED) }.also { started = it }
    }

    fun setUp() {
        val ms = nowMs()
        sessions.clear()
        sessions += listOf(
            AgentSession(
                sessionId = "demo-shellx", agent = "claude", workspaceId = "ws-shellx", workspaceTitle = "shellx",
                title = "Pairing sheet", state = AgentState.WORKING, stateSinceMs = ms - 90_000, lastActivityMs = ms - 5_000,
            ),
            AgentSession(
                sessionId = "demo-web", agent = "claude", workspaceId = "ws-web", workspaceTitle = "web",
                title = "Landing page", state = AgentState.WORKING, stateSinceMs = ms - 300_000, lastActivityMs = ms - 60_000,
            ),
            // Idle, in the same workspace and with the same title as the first: a list that holds both names the
            // second "Pairing sheet · #2".
            AgentSession(
                sessionId = "demo-shellx-2", agent = "claude", workspaceId = "ws-shellx", workspaceTitle = "shellx",
                title = "Pairing sheet", state = AgentState.IDLE, stateSinceMs = ms - 600_000, lastActivityMs = ms - 600_000,
            ),
            // Ended two hours ago: the Ended page has a row.
            AgentSession(
                sessionId = "demo-ended", agent = "claude", workspaceId = "ws-web", workspaceTitle = "web",
                title = "Release 1.5.1", state = AgentState.ENDED, stateSinceMs = ms - 7_200_000,
                lastActivityMs = ms - 7_200_000,
            ),
        )
        for (session in sessions) {
            mac.setHistory(session.sessionId, history(session.workspaceTitle, ms))
            mac.upsertSession(session)
        }
        mac.setWorkspaces(WORKSPACES)
    }

    /** The [index]-th tick (0, 1, 2…). */
    fun step(index: Int) {
        val ms = nowMs()
        val id = "demo-$index-$ms"
        val stepped = sessions.take(2)
        val session = if (stepped.isEmpty()) null else stepped[index % stepped.size]
        val workspace = session?.workspaceTitle ?: "shellx"
        mac.addPending(request(id, index % 3, workspace, ms))
        waiting += id
        while (waiting.size > MAX_PENDING) mac.resolvePending(waiting.removeAt(0))
        if (session == null) return
        val slot = sessions.indexOfFirst { it.sessionId == session.sessionId }.coerceAtLeast(0)
        val old = sessions[slot]
        val flipped = old.copy(
            state = if (old.state == AgentState.WORKING) AgentState.IDLE else AgentState.WORKING,
            stateSinceMs = ms,
            lastActivityMs = ms,
        )
        sessions[slot] = flipped
        // The reply comes first, then the state change, as when Claude Code writes its last message and then stops:
        // the home's "done" note quotes this reply.
        val entry = ChatEntry(
            id = "${flipped.sessionId}-tick-$index", rev = 1, seq = 100L + index, role = ChatEntryRole.AGENT,
            kind = ChatEntryKind.PROSE,
            text = if (flipped.state == AgentState.IDLE) "Xong. Mình đã chạy lại test, tất cả đều xanh." else "Đang làm tiếp…",
            tsMs = ms,
        )
        mac.pushChat(flipped.sessionId, listOf(entry))
        mac.upsertSession(flipped)
    }

    companion object {
        val INTERVAL: Duration = 20.seconds
        const val MAX_PENDING = 6

        /** Steps [start] plays at once: one request of each kind. */
        private const val PLAYED = 3

        /** The Mac's sidebar: one workspace for each session (its terminal names the session), and a third with a
         *  plain shell and no agent. Their ids are the ones the sessions and pending requests carry. */
        val WORKSPACES: List<LinkWorkspace> = listOf(
            LinkWorkspace(
                workspaceId = "ws-shellx", title = "shellx", order = 0, directory = "~/code/shellx", branch = "feat/pairing",
                ports = listOf(3000),
                terminals = listOf(
                    LinkTerminal(terminalId = "demo-shellx-t1", title = "claude", order = 0, selected = true, sessionId = "demo-shellx"),
                    LinkTerminal(terminalId = "demo-shellx-t2", title = "zsh", order = 1, selected = false),
                ),
            ),
            LinkWorkspace(
                workspaceId = "ws-web", title = "web", order = 1, directory = "~/code/web", branch = "main",
                terminals = listOf(
                    LinkTerminal(terminalId = "demo-web-t1", title = "claude", order = 0, selected = true, sessionId = "demo-web"),
                ),
            ),
            LinkWorkspace(
                workspaceId = "ws-docs", title = "docs", order = 2, directory = "~/code/docs",
                terminals = listOf(LinkTerminal(terminalId = "demo-docs-t1", title = "zsh", order = 0, selected = true)),
            ),
        )

        private fun request(id: String, kind: Int, workspace: String, ms: Long): PendingItem = when (kind) {
            0 -> PendingItem(
                requestId = id, kind = PendingKind.PERMISSION, agent = "claude", workspaceId = "ws-$workspace",
                workspaceTitle = workspace, toolName = "Bash",
                toolInputPreview = """{"command":"git push origin feat/pairing","description":"Push the branch"}""",
                createdAtMs = ms, modes = listOf("once", "always", "all", "deny"),
            )
            1 -> PendingItem(
                requestId = id, kind = PendingKind.QUESTION, agent = "claude", workspaceId = "ws-$workspace",
                workspaceTitle = workspace, createdAtMs = ms, modes = emptyList(),
                questions = listOf(
                    PendingQuestion(
                        id = "q1", header = "Màu", prompt = "Nút chính nên dùng màu nào?", multiSelect = false,
                        options = listOf(
                            PendingQuestionOption(id = "blue", label = "Xanh #60a5fa", description = "Màu chính của ShellX"),
                            PendingQuestionOption(id = "gray", label = "Xám", description = "Ít nổi hơn"),
                        ),
                    ),
                    PendingQuestion(
                        id = "q2", header = "Kiểm tra", prompt = "Chạy những bước kiểm tra nào trước khi push?",
                        multiSelect = true,
                        options = listOf(
                            PendingQuestionOption(id = "lint", label = "Lint"),
                            PendingQuestionOption(id = "unit", label = "Unit test", description = "swift test"),
                            PendingQuestionOption(id = "ui", label = "UI test", description = "Chậm, khoảng 5 phút"),
                        ),
                    ),
                ),
            )
            else -> PendingItem(
                requestId = id, kind = PendingKind.EXIT_PLAN, agent = "claude", workspaceId = "ws-$workspace",
                workspaceTitle = workspace, createdAtMs = ms, modes = listOf("auto_accept", "manual", "ultraplan", "deny"),
                planPreview = """
                    ## Ghép cặp Mac

                    1. Thêm `PairingModel` và **test** trước.
                    2. Làm sheet ghép cặp: quét QR, dán mã, xác nhận.
                    3. Danh sách "Máy của bạn" với gỡ ghép cặp.

                    ### Kiểm tra
                    - `swift test` cho ShellXAppCore
                    - Ảnh chụp sáng và tối, tiếng Việt và tiếng Anh
                """.trimIndent(),
            )
        }

        private class Line(
            val role: ChatEntryRole,
            val kind: ChatEntryKind,
            val text: String,
            val toolName: String? = null,
            val truncated: Boolean? = null,
        )

        private fun history(workspace: String, ms: Long): List<ChatEntry> {
            val texts = listOf(
                Line(ChatEntryRole.USER, ChatEntryKind.PROSE, "Sửa giúp mình lỗi build ở $workspace nhé."),
                Line(ChatEntryRole.AGENT, ChatEntryKind.THOUGHT, "Lỗi nằm ở bước link; xem log trước đã."),
                Line(ChatEntryRole.AGENT, ChatEntryKind.TOOL_USE, "swift build", toolName = "Bash"),
                Line(ChatEntryRole.SYSTEM, ChatEntryKind.STATUS, "Đã nén ngữ cảnh."),
                Line(ChatEntryRole.AGENT, ChatEntryKind.PROSE, "Log rất dài… ".repeat(40), truncated = true),
                Line(ChatEntryRole.AGENT, ChatEntryKind.PROSE, "Mình đã sửa import thiếu. Build xanh rồi."),
            )
            return texts.mapIndexed { offset, line ->
                ChatEntry(
                    id = "$workspace-$offset", rev = 1, seq = offset + 1L, role = line.role, kind = line.kind,
                    text = line.text, truncated = line.truncated, toolName = line.toolName,
                    tsMs = ms - (texts.size - offset) * 30_000L,
                )
            }
        }
    }
}
