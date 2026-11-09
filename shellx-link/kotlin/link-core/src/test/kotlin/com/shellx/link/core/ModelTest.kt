package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

class ModelTest {
    /**
     * Global Constraint "Secrets": message content (chat text, previews, plan feedback, answers, attachment names,
     * titles, directories, branches, device and machine names, host error text) never prints. Ids, kinds, counts and
     * sizes stay visible.
     */
    @Test
    fun messageContentNeverPrints() {
        val s = "secret-xyz"
        val option = PendingQuestionOption("o-1", s, s)
        val question = PendingQuestion("q-1", s, s, multiSelect = true, options = listOf(option))
        val item = PendingItem(
            "req-1", PendingKind.QUESTION, "claude", "ws-1", s, toolName = "Bash", toolInputPreview = s, createdAtMs = 7,
            modes = listOf("once"), questions = listOf(question), planPreview = s,
        )
        val session = AgentSession("s-1", "claude", "ws-1", s, title = s, state = AgentState.WORKING)
        val entry = ChatEntry("e-1", 3, 4, ChatEntryRole.USER, ChatEntryKind.PROSE, s, truncated = true, toolName = "Bash", tsMs = 9)
        val terminal = LinkTerminal("t-1", s, 0, selected = true, sessionId = "s-1")
        val workspace = LinkWorkspace("ws-1", s, 0, directory = s, branch = s, ports = listOf(3000), terminals = listOf(terminal))
        val question2 = LinkDecision.Question(listOf(s, s))
        val plan = LinkDecision.ExitPlan(ExitPlanMode.MANUAL, s)
        val values: List<Any> = listOf(
            option, question, item, session, entry, terminal, workspace, question2, plan,
            LinkMessage.Hello("1.0.0", s),
            LinkMessage.Welcome(1, "1.5.0", s, listOf("attachments")),
            LinkMessage.Error("x", s, "c1"),
            LinkMessage.Snapshot("c1", 1, listOf(item)),
            LinkMessage.Changed(2, listOf(item), listOf("req-0")),
            LinkMessage.Reply("c1", "req-1", question2),
            LinkMessage.Reply("c1", "req-1", plan),
            LinkMessage.Sessions("c1", 1, listOf(session)),
            LinkMessage.SessionsChanged(2, listOf(session), listOf("s-0")),
            LinkMessage.ChatHistory("c1", "s-1", listOf(entry), hasMore = false),
            LinkMessage.ChatEntries("s-1", listOf(entry)),
            LinkMessage.ChatSend("c1", "s-1", s, listOf("a-1")),
            LinkMessage.AttachBegin("c1", AttachmentKind.FILE, s, 9),
            LinkMessage.Workspaces("c1", 1, listOf(workspace)),
            LinkMessage.WorkspacesChanged(2, listOf(workspace), listOf("ws-0")),
            LinkMessage.WorkspaceRename("c1", "ws-1", s),
        )
        for (value in values) {
            val text = value.toString()
            assertFalse(s in text, "${value::class.simpleName} printed content: $text".replace(s, "<sentinel>"))
            assertTrue("<redacted>" in text, "${value::class.simpleName} redacts nothing: $text")
        }
        // Ids, kinds, counts and sizes stay visible.
        assertTrue("requestId=req-1" in item.toString() && "toolName=Bash" in item.toString(), item.toString())
        assertTrue("id=e-1" in entry.toString() && "rev=3" in entry.toString(), entry.toString())
        assertTrue("sessionId=s-1" in terminal.toString() && "terminalId=t-1" in terminal.toString(), terminal.toString())
        assertTrue("size=9" in LinkMessage.AttachBegin("c1", AttachmentKind.FILE, s, 9).toString())
        assertTrue("attachments=[a-1]" in LinkMessage.ChatSend("c1", "s-1", s, listOf("a-1")).toString())
        assertTrue("code=x" in LinkMessage.Error("x", s, "c1").toString())
        // An absent optional prints as null, not as <redacted>.
        assertTrue("planPreview=null" in item.copy(planPreview = null).toString(), item.copy(planPreview = null).toString())
    }

    @Test
    fun openEnumsKeepUnknownWireValues() {
        assertEquals(PermissionMode.ONCE, PermissionMode("once"))
        assertEquals("bypass2", PermissionMode("bypass2").wire)
        assertEquals(ExitPlanMode.AUTO_ACCEPT, ExitPlanMode("auto_accept"))
        assertEquals(ReplyOutcome.ALREADY_HANDLED, ReplyOutcome("already_handled"))
        assertEquals(PendingKind.EXIT_PLAN, PendingKind("exit_plan"))
        assertEquals(AgentState.NEEDS_INPUT, AgentState("needs_input"))
        assertEquals(ChatEntryKind.TOOL_USE, ChatEntryKind("tool_use"))
        assertEquals(ChatSendOutcome.NOT_FOUND, ChatSendOutcome("not_found"))
        assertEquals(WorkspaceControlOutcome.REFUSED, WorkspaceControlOutcome("refused"))
    }

    @Test
    fun decisionKindIsTheWireKind() {
        assertEquals("permission", LinkDecision.Permission(PermissionMode.ONCE).kind)
        assertEquals("question", LinkDecision.Question(listOf("a")).kind)
        assertEquals("exit_plan", LinkDecision.ExitPlan(ExitPlanMode.MANUAL).kind)
        assertEquals("teleport", LinkDecision.Other("teleport").kind)
    }

    @Test
    fun newerEntryRevisionWins() {
        val a = ChatEntry("e", 3, 1, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "old", tsMs = 1)
        val b = a.copy(rev = 4, text = "new")
        assertEquals(b, ChatEntry.newer(a, b))
        assertEquals(b, ChatEntry.newer(b, a))
        assertEquals(a, ChatEntry.newer(a, a.copy(text = "same rev")))
    }

    @Test
    fun constantsMatchTheSwiftPackage() {
        assertEquals(10_485_760, ShellXLink.MAX_ATTACHMENT_BYTES)
        assertEquals(5, ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE)
        assertEquals(5, ShellXLink.MAX_PENDING_UPLOADS)
        assertEquals(45_000, ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES)
        assertEquals(300.seconds, ShellXLink.UNSENT_UPLOAD_LIFETIME)
        assertEquals(512, ShellXLink.MAX_WORKSPACE_TITLE_BYTES)
        assertEquals(4096, ChatEntry.MAX_TEXT_BYTES)
        assertEquals(8192, PendingItem.MAX_PREVIEW_BYTES)
        assertEquals(
            listOf("attachments", "workspaces", "workspace_control", "agent_close", "terminal_close"),
            listOf(
                ShellXLink.ATTACHMENTS_FEATURE, ShellXLink.WORKSPACES_FEATURE, ShellXLink.WORKSPACE_CONTROL_FEATURE,
                ShellXLink.AGENT_CLOSE_FEATURE, ShellXLink.TERMINAL_CLOSE_FEATURE,
            ),
        )
    }
}
