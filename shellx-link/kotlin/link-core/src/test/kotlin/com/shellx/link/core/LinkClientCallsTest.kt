package com.shellx.link.core

import com.shellx.link.core.LinkMessage as M
import com.shellx.link.core.Samples.entry
import com.shellx.link.core.Samples.item
import com.shellx.link.core.Samples.session
import com.shellx.link.core.Samples.workspace
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking

class LinkClientCallsTest {
    @Test
    fun everyCallSendsItsRequestAndUnpacksItsAnswer() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val requests = CopyOnWriteArrayList<M>()
                val served = async {
                    assertFailsWith<RelayException.Closed> {
                        while (true) {
                            val request = channel.request()
                            requests += request
                            channel.send(answer(request))
                        }
                    }
                }

                assertEquals(PendingSnapshot(7, listOf(item)), client.snapshot())
                assertEquals(ReplyOutcome.DELIVERED, client.reply("req-1", LinkDecision.Question(listOf("Postgres"))))
                assertEquals(SessionList(4, listOf(session)), client.sessions())
                assertEquals(ChatHistoryPage(listOf(entry), true), client.chatHistory("s-1", 40, 20))
                assertEquals(ChatSendOutcome.SUBMITTED, client.chatSend("s-1", "fix", listOf("a1")))
                assertEquals(ChatInterruptOutcome.SENT, client.chatInterrupt("s-1", hard = true))
                assertEquals(WorkspaceList(6, listOf(workspace)), client.workspaces())
                assertEquals(WorkspaceCreated(WorkspaceControlOutcome.OK, "ws-3"), client.createWorkspace())
                assertEquals(WorkspaceControlOutcome.OK, client.renameWorkspace("ws-2", "Docs — v2"))
                assertEquals(WorkspaceControlOutcome.REFUSED, client.closeWorkspace("ws-2"))
                assertEquals(WorkspaceControlOutcome.NOT_FOUND, client.closeAgent("sess-1"))
                assertEquals(WorkspaceControlOutcome.OK, client.closeTerminal("ws-1", "t-1"))
                assertEquals(ChatHistoryPage(listOf(entry), true), client.chatHistory("s-1", null, 50))
                client.close()
                served.await()

                // The recorded requests carry the arguments, call ids aside.
                assertEquals(
                    listOf(
                        M.SnapshotGet(""),
                        M.Reply("", "req-1", LinkDecision.Question(listOf("Postgres"))),
                        M.SessionsGet(""),
                        M.ChatHistoryGet("", "s-1", 40, 20),
                        M.ChatSend("", "s-1", "fix", listOf("a1")),
                        M.ChatInterrupt("", "s-1", true),
                        M.WorkspacesGet(""),
                        M.WorkspaceCreate(""),
                        M.WorkspaceRename("", "ws-2", "Docs — v2"),
                        M.WorkspaceClose("", "ws-2"),
                        M.AgentClose("", "sess-1"),
                        M.TerminalClose("", "ws-1", "t-1"),
                        M.ChatHistoryGet("", "s-1", null, 50),
                    ),
                    requests.map(::withoutCallId),
                )
                assertEquals(requests.size, requests.map(::callId).toSet().size, "call ids repeat")
            }
        }
    }

    private fun answer(request: M): M = when (request) {
        is M.SnapshotGet -> M.Snapshot(request.callId, 7, listOf(item))
        is M.Reply -> M.ReplyResult(request.callId, request.requestId, ReplyOutcome.DELIVERED)
        is M.SessionsGet -> M.Sessions(request.callId, 4, listOf(session))
        is M.ChatHistoryGet -> M.ChatHistory(request.callId, request.sessionId, listOf(entry), true)
        is M.ChatSend -> M.ChatSendResult(request.callId, ChatSendOutcome.SUBMITTED)
        is M.ChatInterrupt -> M.ChatInterruptResult(request.callId, ChatInterruptOutcome.SENT)
        is M.WorkspacesGet -> M.Workspaces(request.callId, 6, listOf(workspace))
        is M.WorkspaceCreate -> M.WorkspaceCreateResult(request.callId, WorkspaceControlOutcome.OK, "ws-3")
        is M.WorkspaceRename -> M.WorkspaceRenameResult(request.callId, WorkspaceControlOutcome.OK)
        is M.WorkspaceClose -> M.WorkspaceCloseResult(request.callId, WorkspaceControlOutcome.REFUSED)
        is M.AgentClose -> M.AgentCloseResult(request.callId, WorkspaceControlOutcome.NOT_FOUND)
        is M.TerminalClose -> M.TerminalCloseResult(request.callId, WorkspaceControlOutcome.OK)
        else -> error("unexpected request ${request::class.simpleName}")
    }

    private fun callId(request: M): String = when (request) {
        is M.SnapshotGet -> request.callId
        is M.Reply -> request.callId
        is M.SessionsGet -> request.callId
        is M.ChatHistoryGet -> request.callId
        is M.ChatSend -> request.callId
        is M.ChatInterrupt -> request.callId
        is M.WorkspacesGet -> request.callId
        is M.WorkspaceCreate -> request.callId
        is M.WorkspaceRename -> request.callId
        is M.WorkspaceClose -> request.callId
        is M.AgentClose -> request.callId
        is M.TerminalClose -> request.callId
        else -> error("unexpected request ${request::class.simpleName}")
    }

    private fun withoutCallId(request: M): M = when (request) {
        is M.SnapshotGet -> request.copy(callId = "")
        is M.Reply -> request.copy(callId = "")
        is M.SessionsGet -> request.copy(callId = "")
        is M.ChatHistoryGet -> request.copy(callId = "")
        is M.ChatSend -> request.copy(callId = "")
        is M.ChatInterrupt -> request.copy(callId = "")
        is M.WorkspacesGet -> request.copy(callId = "")
        is M.WorkspaceCreate -> request.copy(callId = "")
        is M.WorkspaceRename -> request.copy(callId = "")
        is M.WorkspaceClose -> request.copy(callId = "")
        is M.AgentClose -> request.copy(callId = "")
        is M.TerminalClose -> request.copy(callId = "")
        else -> request
    }
}
