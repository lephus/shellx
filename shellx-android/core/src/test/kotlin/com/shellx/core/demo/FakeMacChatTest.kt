package com.shellx.core.demo

import com.shellx.core.testing.agentSession
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.chatEntry
import com.shellx.core.testing.eventually
import com.shellx.core.testing.linkTerminal
import com.shellx.core.testing.linkWorkspace
import com.shellx.link.core.AgentState
import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ChatAttachment
import com.shellx.link.core.ChatHistoryPage
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatPush
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkSession
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.MessageUploadException
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.WorkspaceControlOutcome
import com.shellx.link.core.WorkspaceCreated
import java.util.Collections
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class FakeMacChatTest {
    private val phone = NoiseStaticKey.generate()

    private suspend fun connect(mac: FakeMac): LinkSession = mac.connector { phone }.connect(mac.machine)

    @Test fun historyPagesFromTheNewestAndBeforeASeq() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", (1L..30L).map { chatEntry(it) })
        val session = connect(mac)
        assertEquals(ChatHistoryPage((21L..30L).map { chatEntry(it) }, true), session.chatHistory("s1", null, 10))
        assertEquals(ChatHistoryPage((11L..20L).map { chatEntry(it) }, true), session.chatHistory("s1", 21, 10))
        assertEquals(ChatHistoryPage((1L..10L).map { chatEntry(it) }, false), session.chatHistory("s1", 11, 50))
        assertEquals(
            listOf(FakeMac.HistoryRequest("s1", null, 10), FakeMac.HistoryRequest("s1", 21, 10), FakeMac.HistoryRequest("s1", 11, 50)),
            mac.historyRequests,
        )
    } }

    @Test fun historyRules() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        for (limit in listOf(0, 51)) {
            assertSameCase(
                LinkClientException.Remote("bad_request", "limit must be 1 to 50"),
                assertFails { session.chatHistory("s1", null, limit) },
            )
        }
        assertSameCase(LinkClientException.Remote("not_found", "no such session"), assertFails { session.chatHistory("s9", null, 10) })
        // As the host: a refused limit never reaches the transcript, so only the unknown session is recorded.
        assertEquals(listOf(FakeMac.HistoryRequest("s9", null, 10)), mac.historyRequests)
        val bare = FakeMac("Mac mini", backgroundScope, servesSessionsAndChat = false)
        assertSameCase(
            LinkClientException.Remote("unsupported", "this host has no chat"),
            assertFails { connect(bare).chatHistory("s1", null, 10) },
        )
    } }

    @Test fun pushAndResetReachChatEntriesInOrder() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val session = connect(mac)
        mac.pushChat("s1", listOf(chatEntry(7)))
        mac.resetChat("s1", listOf(chatEntry(1)))
        mac.pushChat("s1", listOf(chatEntry(2)))
        assertEquals(
            listOf(ChatPush.Upsert("s1", listOf(chatEntry(7))), ChatPush.Reset("s1"), ChatPush.Upsert("s1", listOf(chatEntry(2)))),
            session.chatEntries.take(3).toList(),
        )
        assertEquals(listOf(1L, 2L), session.chatHistory("s1", null, 50).entries.map { it.seq })
    } }

    @Test fun sendAndInterruptOutcomes() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        assertEquals(ChatSendOutcome.SUBMITTED, session.chatSend("s1", "hi"))
        assertEquals(ChatInterruptOutcome.SENT, session.chatInterrupt("s1", false))
        assertEquals(ChatSendOutcome.NOT_FOUND, session.chatSend("nope", "hi"))
        assertEquals(ChatInterruptOutcome.NOT_FOUND, session.chatInterrupt("nope", true))
        mac.setSendOutcome(ChatSendOutcome.BUSY)
        mac.setInterruptOutcome(ChatInterruptOutcome.FAILED)
        assertEquals(ChatSendOutcome.BUSY, session.chatSend("s1", "x"))
        assertEquals(ChatInterruptOutcome.FAILED, session.chatInterrupt("s1", true))
        mac.setSendOutcome(null)
        assertSameCase(
            LinkClientException.Remote("bad_request", "text must be 1 to 16384 bytes"),
            assertFails { session.chatSend("s1", "") },
        )
        assertSameCase(
            LinkClientException.Remote("bad_request", "text must be 1 to 16384 bytes"),
            assertFails { session.chatSend("s1", "a".repeat(16_385)) },
        )
        assertEquals(ChatSendOutcome.SUBMITTED, session.chatSend("s1", "a".repeat(16_384)))
        assertEquals(
            listOf(
                FakeMac.SentText("s1", "hi"), FakeMac.SentText("nope", "hi"), FakeMac.SentText("s1", "x"),
                FakeMac.SentText("s1", "a".repeat(16_384)),
            ),
            mac.sentTexts,
        )
        assertEquals(
            listOf(FakeMac.Interrupt("s1", false), FakeMac.Interrupt("nope", true), FakeMac.Interrupt("s1", true)),
            mac.interrupts,
        )
    } }

    @Test fun heldChatCallsActAfterRelease() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        mac.holdChat()
        val call = backgroundScope.async { session.chatSend("s1", "x") }
        assertTrue(eventually { mac.sentTexts.size == 1 })
        runCurrent()
        assertFalse(call.isCompleted)
        mac.releaseChat()
        assertEquals(ChatSendOutcome.SUBMITTED, call.await())
    } }

    @Test fun attachmentsUploadInChunksAndArriveWithTheMessage() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        val big = ChatAttachment(AttachmentKind.FILE, "big", ByteArray(100_000))
        val small = ChatAttachment(AttachmentKind.IMAGE, "small.jpg", ByteArray(3))
        val progress = mutableListOf<Int>()
        assertEquals(ChatSendOutcome.SUBMITTED, session.chatSend("s1", "x", uploading = listOf(big, small)) { progress += it })
        assertEquals(listOf(45_000, 90_000, 100_000, 100_003), progress)
        assertEquals(listOf(big, small), mac.receivedAttachments)
        assertEquals(listOf(FakeMac.SentText("s1", "x")), mac.sentTexts)
    } }

    @Test fun attachmentRulesRefuseBeforeTyping() { runTest {
        val photo = ChatAttachment(AttachmentKind.IMAGE, "photo.jpg", ByteArray(3))
        val bare = FakeMac("Mac mini", backgroundScope, acceptsAttachments = false)
        bare.setHistory("s1", listOf(chatEntry(1)))
        assertSameCase(
            MessageUploadException(LinkClientException.Remote("unsupported", "this host takes no attachments")),
            assertFails { connect(bare).chatSend("s1", "x", uploading = listOf(photo)) },
        )
        assertEquals(emptyList(), bare.sentTexts)
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        val huge = ChatAttachment(AttachmentKind.FILE, "huge", ByteArray(10_485_761))
        assertSameCase(
            MessageUploadException(LinkClientException.Remote("too_large", "size is above 10485760 bytes")),
            assertFails { session.chatSend("s1", "x", uploading = listOf(photo, huge)) },
        )
        assertEquals(emptyList(), mac.sentTexts)
        val empty = ChatAttachment(AttachmentKind.FILE, "empty", ByteArray(0))
        assertSameCase(
            MessageUploadException(LinkClientException.Remote("bad_request", "size must be at least 1")),
            assertFails { session.chatSend("s1", "x", uploading = listOf(empty)) },
        )
        assertEquals(emptyList(), mac.sentTexts)
        assertEquals(emptyList(), mac.receivedAttachments)
    } }

    @Test fun oneMessageUploadsAtATime() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        fun files(prefix: String) = (0..4).map { ChatAttachment(AttachmentKind.FILE, "$prefix$it", ByteArray(50_000)) }
        val chunks = Collections.synchronizedList(mutableListOf<String>())
        val one = backgroundScope.async { session.chatSend("s1", "one", uploading = files("a")) { chunks += "one" } }
        val two = backgroundScope.async { session.chatSend("s1", "two", uploading = files("b")) { chunks += "two" } }
        assertEquals(ChatSendOutcome.SUBMITTED, one.await())
        assertEquals(ChatSendOutcome.SUBMITTED, two.await())
        val a = (0..4).map { "a$it" }
        val b = (0..4).map { "b$it" }
        val names = mac.receivedAttachments.map { it.name }
        assertTrue(names == a + b || names == b + a, "mixed: $names")
        // Each message holds the turn for all of its chunks (two per attachment), so they never interleave.
        val ones = List(10) { "one" }
        val twos = List(10) { "two" }
        assertTrue(chunks == ones + twos || chunks == twos + ones, "interleaved: $chunks")
    } }

    // An upload is driven by the phone, chunk by chunk, as 3B's client does: once the call has ended (the session
    // closed, or the caller was cancelled) nothing more goes up, and the message is never typed.

    @Test fun aMessageWhoseSessionEndsWhileUploadingIsNeverTyped() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        val big = ChatAttachment(AttachmentKind.FILE, "big", ByteArray(100_000))
        val progress = mutableListOf<Int>()
        val error = assertFails {
            session.chatSend("s1", "x", uploading = listOf(big)) {
                progress += it
                if (it == 45_000) session.close()
            }
        }
        assertSameCase(MessageUploadException(LinkClientException.SessionClosed()), error)
        assertFalse(eventually(timeout = 1.seconds) { mac.sentTexts.isNotEmpty() || mac.receivedAttachments.isNotEmpty() })
        assertEquals(listOf(45_000), progress, "no progress after the end")
    } }

    @Test fun aMessageWhoseCallerIsCancelledWhileUploadingIsNeverTyped() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        val big = ChatAttachment(AttachmentKind.FILE, "big", ByteArray(100_000))
        val progress = mutableListOf<Int>()
        lateinit var call: Job
        call = backgroundScope.launch {
            session.chatSend("s1", "x", uploading = listOf(big)) {
                progress += it
                if (it == 45_000) call.cancel()
            }
        }
        call.join()
        assertTrue(call.isCancelled)
        assertFalse(eventually(timeout = 1.seconds) { mac.sentTexts.isNotEmpty() || mac.receivedAttachments.isNotEmpty() })
        assertEquals(listOf(45_000), progress, "no progress after the end")
        // The session lives on, and the cancelled message gave up its upload turn.
        val small = ChatAttachment(AttachmentKind.IMAGE, "small.jpg", ByteArray(3))
        assertEquals(ChatSendOutcome.SUBMITTED, session.chatSend("s1", "after", uploading = listOf(small)))
        assertEquals(listOf(FakeMac.SentText("s1", "after")), mac.sentTexts)
        assertEquals(listOf(small), mac.receivedAttachments)
    } }

    @Test fun anUploadThatEndsEarlyIsNotKept() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.setHistory("s1", listOf(chatEntry(1)))
        val session = connect(mac)
        val data = ByteArray(100_000)
        // The caller is cancelled after the first chunk: nothing more goes up, and no upload is kept.
        val progress = mutableListOf<Int>()
        lateinit var call: Job
        call = backgroundScope.launch {
            session.uploadAttachment(AttachmentKind.FILE, "big", data) {
                progress += it
                if (it == 45_000) call.cancel()
            }
        }
        call.join()
        assertFalse(eventually(timeout = 1.seconds) { progress.size > 1 }, "no progress after the end: $progress")
        assertSameCase(
            LinkClientException.Remote("bad_request", "an attachment is not held, or not finished"),
            assertFails { session.chatSend("s1", "x", attachments = listOf("U1")) },
        )
        // A whole upload is kept and arrives with the message that names it.
        val id = session.uploadAttachment(AttachmentKind.FILE, "whole", ByteArray(3))
        assertEquals(ChatSendOutcome.SUBMITTED, session.chatSend("s1", "y", attachments = listOf(id)))
        assertEquals(listOf("whole"), mac.receivedAttachments.map { it.name })
        // The session ends after the first chunk: the upload throws SessionClosed and reports nothing more.
        val ended = mutableListOf<Int>()
        assertSameCase(
            LinkClientException.SessionClosed(),
            assertFails {
                session.uploadAttachment(AttachmentKind.FILE, "late", data) {
                    ended += it
                    if (it == 45_000) session.close()
                }
            },
        )
        assertFalse(eventually(timeout = 1.seconds) { ended.size > 1 }, "no progress after the end: $ended")
    } }

    @Test fun workspaceControlActsLikeTheMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val session = connect(mac)
        assertEquals(WorkspaceCreated(WorkspaceControlOutcome.OK, "ws-new-1"), session.createWorkspace())
        val created = session.workspaces().workspaces.single()
        assertEquals("ws-new-1", created.workspaceId)
        assertEquals("Workspace 1", created.title)
        assertEquals(listOf(LinkTerminal("ws-new-1-t1", "zsh", 0, true)), created.terminals)
        assertEquals(WorkspaceControlOutcome.OK, session.renameWorkspace("ws-new-1", "Docs"))
        assertEquals("Docs", session.workspaces().workspaces.single().title)
        assertEquals(WorkspaceControlOutcome.NOT_FOUND, session.renameWorkspace("nope", "x"))
        assertEquals(WorkspaceControlOutcome.REFUSED, session.closeWorkspace("ws-new-1"))
        assertEquals(WorkspaceCreated(WorkspaceControlOutcome.OK, "ws-new-2"), session.createWorkspace())
        assertEquals(WorkspaceControlOutcome.OK, session.closeWorkspace("ws-new-1"))
        assertEquals(listOf("ws-new-2"), session.workspaces().workspaces.map { it.workspaceId })
        assertSameCase(
            LinkClientException.Remote("bad_request", "title must be at most 512 bytes"),
            assertFails { session.renameWorkspace("ws-new-2", "a".repeat(513)) },
        )
        mac.setNextWorkspaceOutcome(WorkspaceControlOutcome.FAILED)
        assertEquals(WorkspaceControlOutcome.FAILED, session.renameWorkspace("ws-new-2", "Lost"))
        assertEquals("Workspace 2", session.workspaces().workspaces.single().title)
        mac.setNextWorkspaceOutcome(WorkspaceControlOutcome.FAILED)
        assertEquals(WorkspaceCreated(WorkspaceControlOutcome.FAILED, null), session.createWorkspace())
        assertEquals(listOf("ws-new-2"), session.workspaces().workspaces.map { it.workspaceId })
        assertEquals(
            listOf(
                "create", "rename:ws-new-1:Docs", "rename:nope:x", "close:ws-new-1", "create", "close:ws-new-1",
                "rename:ws-new-2:Lost", "create",
            ),
            mac.workspaceCalls,
        )
    } }

    @Test fun agentAndTerminalClose() { runTest {
        val now = 1_700_000_100_000L
        val mac = FakeMac("MacBook Pro", backgroundScope, nowMs = { now })
        mac.upsertSession(agentSession("s1"))
        mac.setWorkspaces(
            listOf(
                linkWorkspace("a", terminals = listOf(linkTerminal("t1"))),
                linkWorkspace("b", order = 1, terminals = listOf(linkTerminal("t2"), linkTerminal("t3", order = 1))),
            ),
        )
        val session = connect(mac)
        assertEquals(WorkspaceControlOutcome.OK, session.closeAgent("s1"))
        assertEquals(
            listOf(agentSession("s1", state = AgentState.ENDED, lastActivityMs = now, stateSinceMs = now)),
            session.sessionChanges.first().upserted,
        )
        assertEquals(WorkspaceControlOutcome.NOT_FOUND, session.closeAgent("s1"))
        assertEquals(WorkspaceControlOutcome.NOT_FOUND, session.closeAgent("nope"))
        assertEquals(WorkspaceControlOutcome.NOT_FOUND, session.closeTerminal("ws-a", "t2"))
        assertEquals(WorkspaceControlOutcome.OK, session.closeTerminal("ws-a", "t1"))
        assertEquals(listOf("ws-b"), session.workspaces().workspaces.map { it.workspaceId })
        assertEquals(WorkspaceControlOutcome.OK, session.closeTerminal("ws-b", "t2"))
        assertEquals(listOf("t3"), session.workspaces().workspaces.single().terminals.map { it.terminalId })
        mac.setNextTerminalCloseOutcome(WorkspaceControlOutcome.REFUSED)
        assertEquals(WorkspaceControlOutcome.REFUSED, session.closeTerminal("ws-b", "t3"))
        assertEquals(listOf("t3"), session.workspaces().workspaces.single().terminals.map { it.terminalId })
        mac.holdWorkspaceControl()
        val agent = backgroundScope.async { session.closeAgent("s2") }
        val terminal = backgroundScope.async { session.closeTerminal("ws-b", "t3") }
        assertTrue(eventually { mac.agentCloses.size == 4 && mac.terminalCloses.size == 5 })
        runCurrent()
        assertFalse(agent.isCompleted)
        assertFalse(terminal.isCompleted)
        mac.releaseWorkspaceControl()
        assertEquals(WorkspaceControlOutcome.NOT_FOUND, agent.await())
        assertEquals(WorkspaceControlOutcome.OK, terminal.await())
        assertEquals(emptyList(), session.workspaces().workspaces)
        assertEquals(listOf("s1", "s1", "nope", "s2"), mac.agentCloses)
        assertEquals(
            listOf(
                FakeMac.TerminalCloseCall("ws-a", "t2"), FakeMac.TerminalCloseCall("ws-a", "t1"),
                FakeMac.TerminalCloseCall("ws-b", "t2"), FakeMac.TerminalCloseCall("ws-b", "t3"),
                FakeMac.TerminalCloseCall("ws-b", "t3"),
            ),
            mac.terminalCloses,
        )
    } }

    @Test fun controlIsUnsupportedWithoutItsFeature() { runTest {
        val noControl = FakeMac("Mac mini", backgroundScope, acceptsWorkspaceControl = false)
        val noWorkspaces = FakeMac("Mac Studio", backgroundScope, servesWorkspaces = false)
        for (mac in listOf(noControl, noWorkspaces)) {
            val session = connect(mac)
            val unsupported = LinkClientException.Remote("unsupported", "this host takes no workspace control")
            assertSameCase(unsupported, assertFails { session.createWorkspace() })
            assertSameCase(unsupported, assertFails { session.renameWorkspace("ws-a", "x") })
            assertSameCase(unsupported, assertFails { session.closeWorkspace("ws-a") })
            assertEquals(emptyList(), mac.workspaceCalls)
        }
        val noAgentClose = FakeMac("iMac", backgroundScope, acceptsAgentClose = false)
        val noSessions = FakeMac("Mac Pro", backgroundScope, servesSessionsAndChat = false)
        for (mac in listOf(noAgentClose, noSessions)) {
            assertSameCase(
                LinkClientException.Remote("unsupported", "this host takes no agent control"),
                assertFails { connect(mac).closeAgent("s1") },
            )
            assertEquals(emptyList(), mac.agentCloses)
        }
        val noTerminalClose = FakeMac("MacBook Air", backgroundScope, acceptsTerminalClose = false)
        assertSameCase(
            LinkClientException.Remote("unsupported", "this host takes no terminal control"),
            assertFails { connect(noTerminalClose).closeTerminal("ws-a", "t1") },
        )
        assertEquals(emptyList(), noTerminalClose.terminalCloses)
    } }
}
