package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Duration.Companion.seconds

class ModelTest {
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
