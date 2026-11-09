package com.shellx.link.core

import com.shellx.link.core.LinkClientException.ProtocolMismatch
import com.shellx.link.core.LinkMessage.Error
import com.shellx.link.core.Samples.entry
import com.shellx.link.core.Samples.item
import com.shellx.link.core.Samples.session
import com.shellx.link.core.Samples.workspace
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class LinkClientTest {
    private val once = LinkDecision.Permission(PermissionMode.ONCE)

    @Test
    fun helloCarriesVersionAndNameAndFeaturesAreKept() {
        runBlocking {
            within {
                val rig = HostRig(features = listOf("attachments", "teleport"))
                val host = async { rig.host() }
                val client = rig.client()
                val (_, hello) = host.await()
                assertEquals(LinkMessage.Hello("test-client", "Test Phone"), hello)
                assertEquals(setOf("attachments", "teleport"), client.hostFeatures)
                val asSession: LinkSession = client
                asSession.close()
            }
        }
    }

    @Test
    fun welcomeErrorsFailTheConnect() {
        runBlocking {
            within {
                val cases = listOf(
                    Error("protocol_mismatch", "update the app") to ProtocolMismatch("update the app"),
                    Error("bad_request", "nope") to LinkClientException.Rejected("bad_request", "nope"),
                    LinkMessage.Welcome(2, "test-host", "Test Mac") to ProtocolMismatch("the host speaks protocol 2"),
                )
                for ((answer, expected) in cases) {
                    val rig = HostRig()
                    val host = async {
                        val channel = rig.handshake()
                        channel.receive() as LinkMessage.Hello
                        channel.send(answer)
                        channel
                    }
                    assertEquals(expected, assertFailsWith<LinkClientException> { rig.client() })
                    assertFailsWith<RelayException.Closed> { host.await().receive() }
                }
            }
        }
    }

    @Test
    fun wrongHostKeyFailsBeforeMessage3() {
        runBlocking {
            within {
                val rig = HostRig()
                val impostor = async {
                    val responder = NoiseHandshake(NoiseRole.RESPONDER, NoiseStaticKey.generate())
                    responder.readMessage(rig.hostEnd.receive())
                    rig.hostEnd.send(responder.writeMessage())
                }
                assertFailsWith<NoiseException.UntrustedPeer> { rig.client() }
                impostor.await()
                assertFailsWith<RelayException.Closed> { rig.hostEnd.receive() }
            }
        }
    }

    @Test
    fun framesBeforeWelcomeAreIgnored() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async {
                    val channel = rig.handshake()
                    channel.receive() as LinkMessage.Hello
                    channel.sendFrame("""{"v":1,"t":"agent.changed","revision":1}""".encodeToByteArray())
                    channel.send(LinkMessage.Changed(1, emptyList(), emptyList()))
                    channel.send(LinkMessage.Welcome(1, "test-host", "Test Mac", listOf("workspaces")))
                    channel
                }
                val client = rig.client()
                assertEquals(setOf("workspaces"), client.hostFeatures)
                // The change sent before welcome never reaches the Flow.
                host.await().send(LinkMessage.Changed(2, emptyList(), emptyList()))
                assertEquals(2, client.changes.first().revision)
                client.close()
            }
        }
    }

    @Test
    fun callIdsAreUniqueAndAnswersMatch() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val first = async { client.reply("r1", once) }
                val second = async { client.reply("r1", once) }
                val a = channel.request() as LinkMessage.Reply
                val b = channel.request() as LinkMessage.Reply
                assertNotEquals(a.callId, b.callId)
                for (id in listOf(a.callId, b.callId)) assertTrue(id.utf8Size in 1..64, id)
                channel.send(LinkMessage.ReplyResult(b.callId, "r1", ReplyOutcome.DELIVERED))
                channel.send(LinkMessage.ReplyResult(a.callId, "r1", ReplyOutcome.DELIVERED))
                assertEquals(listOf(ReplyOutcome.DELIVERED, ReplyOutcome.DELIVERED), listOf(first.await(), second.await()))
                client.close()
            }
        }
    }

    @Test
    fun lateAnswerOfATimedOutCallIsDropped() {
        runBlocking {
            within {
                val rig = HostRig(timings = LinkTimings(20.seconds, 45.seconds, requestTimeout = 300.milliseconds))
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val first = async { assertFailsWith<LinkClientException.TimedOut> { client.reply("r1", once) } }
                val held = channel.request() as LinkMessage.Reply
                first.await()
                val retry = async { client.reply("r1", once) }
                val second = channel.request() as LinkMessage.Reply
                channel.send(LinkMessage.ReplyResult(held.callId, "r1", ReplyOutcome.DELIVERED))
                channel.send(LinkMessage.ReplyResult(second.callId, "r1", ReplyOutcome.ALREADY_HANDLED))
                assertEquals(ReplyOutcome.ALREADY_HANDLED, retry.await())
                assertEquals(0, client.pendingCalls)
                client.close()
            }
        }
    }

    @Test
    fun remoteErrorFailsOnlyThatCall() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val failing = async { assertFailsWith<LinkClientException.Remote> { client.reply("r1", once) } }
                val reply = channel.request() as LinkMessage.Reply
                channel.send(Error("bad_request", "nope", reply.callId))
                assertEquals(LinkClientException.Remote("bad_request", "nope"), failing.await())
                val snapshot = async { client.snapshot() }
                val get = channel.request() as LinkMessage.SnapshotGet
                channel.send(LinkMessage.Snapshot(get.callId, 3, emptyList()))
                assertEquals(3, snapshot.await().revision)
                client.close()
            }
        }
    }

    @Test
    fun answerOfAnotherTypeIsUnexpectedAnswer() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val call = async { assertFailsWith<LinkClientException.UnexpectedAnswer> { client.snapshot() } }
                val get = channel.request() as LinkMessage.SnapshotGet
                channel.send(LinkMessage.ChatSendResult(get.callId, ChatSendOutcome.SUBMITTED))
                call.await()
                client.close()
            }
        }
    }

    @Test
    fun clientOnlyFramesNeverAnswerACall() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val call = async { client.call { LinkMessage.AttachBegin(it, AttachmentKind.FILE, "x", 1) } }
                val id = (channel.request() as LinkMessage.AttachBegin).callId
                channel.send(LinkMessage.AttachBegin(id, AttachmentKind.FILE, "x", 1))
                channel.send(LinkMessage.AttachChunk(id, "a1", 0, byteArrayOf(1)))
                channel.send(LinkMessage.AttachEnd(id, "a1", ByteArray(32)))
                channel.send(LinkMessage.AttachReady(id, "a1"))
                assertEquals(LinkMessage.AttachReady(id, "a1"), call.await())
                client.close()
            }
        }
    }

    @Test
    fun pushesReachTheirFlowsInOrder() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                channel.send(LinkMessage.Changed(1, listOf(item), emptyList()))
                channel.send(LinkMessage.SessionsChanged(1, listOf(session), emptyList()))
                channel.send(LinkMessage.WorkspacesChanged(1, listOf(workspace), emptyList()))
                channel.send(LinkMessage.ChatEntries("s-1", listOf(entry)))
                channel.send(LinkMessage.ChatReset("s-1"))
                channel.send(LinkMessage.Changed(2, emptyList(), listOf("r1")))
                assertEquals(
                    listOf(PendingChange(1, listOf(item), emptyList()), PendingChange(2, emptyList(), listOf("r1"))),
                    client.changes.take(2).toList(),
                )
                assertEquals(listOf(ChatPush.Upsert("s-1", listOf(entry)), ChatPush.Reset("s-1")), client.chatEntries.take(2).toList())
                assertEquals(SessionChange(1, listOf(session), emptyList()), client.sessionChanges.first())
                assertEquals(WorkspaceChange(1, listOf(workspace), emptyList()), client.workspaceChanges.first())
                assertEquals(emptyList(), ChatPush.Reset("s-1").entries)
                client.close()
            }
        }
    }

    @Test
    fun undecodableFrameIsDroppedAndTheNextArrives() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                channel.sendFrame("""{"v":1,"t":"agent.changed","revision":1}""".encodeToByteArray())
                channel.send(LinkMessage.Changed(2, emptyList(), emptyList()))
                assertEquals(2, client.changes.first().revision)
                client.close()
            }
        }
    }

    @Test
    fun protocolMismatchEndsTheSession() {
        runBlocking {
            within {
                // The host's `error protocol_mismatch`, then a frame of another version.
                val cases = listOf(ProtocolMismatch("update"), ProtocolMismatch("the host sent another protocol version"))
                for ((index, expected) in cases.withIndex()) {
                    val rig = HostRig()
                    val host = async { rig.host() }
                    val client = rig.client()
                    val (channel, _) = host.await()
                    val pending = async { assertFailsWith<ProtocolMismatch> { client.snapshot() } }
                    channel.request() as LinkMessage.SnapshotGet
                    if (index == 0) {
                        channel.send(Error("protocol_mismatch", "update"))
                    } else {
                        channel.sendFrame("""{"v":2,"t":"ping","nonce":1}""".encodeToByteArray())
                    }
                    assertEquals(expected, pending.await())
                    assertEquals(emptyList(), client.changes.toList())
                    assertEquals(expected, assertFailsWith<ProtocolMismatch> { client.snapshot() })
                    assertFailsWith<RelayException.Closed> { channel.receive() }
                }
            }
        }
    }

    @Test
    fun hostPingWithAnyUint64NonceIsEchoed() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                for (nonce in listOf(ULong.MAX_VALUE, 9_223_372_036_854_775_808u, 0u)) {
                    channel.send(LinkMessage.Ping(nonce))
                    assertEquals(LinkMessage.Pong(nonce), channel.receive())
                }
                client.close()
            }
        }
    }

    @Test
    fun clientPingsEveryIntervalWithConsecutiveNonces() {
        runBlocking {
            within {
                val rig = HostRig(timings = LinkTimings(pingInterval = 50.milliseconds, idleTimeout = 45.seconds))
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val pings = within(1.seconds) { List(3) { channel.receive() as LinkMessage.Ping } }
                pings.zipWithNext { a, b -> assertEquals(a.nonce + 1u, b.nonce) }
                client.close()
            }
        }
    }

    @Test
    fun pingNoncesWrapAtTheTopOfUint64() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                val rig = HostRig()
                val host = async { SecureChannel.open(b, NoiseRole.RESPONDER, rig.hostKey) { true } }
                val channel = SecureChannel.open(a, NoiseRole.INITIATOR, rig.clientKey) { true }
                val server = host.await()
                val pinger = launch { runPings(channel, 10.milliseconds, start = ULong.MAX_VALUE - 1u) }
                val nonces = List(3) { (server.receive() as LinkMessage.Ping).nonce }
                pinger.cancelAndJoin()
                assertEquals(listOf(ULong.MAX_VALUE, 0uL, 1uL), nonces)
                channel.close()
            }
        }
    }

    @Test
    fun closeFailsPendingCallsAndCompletesEveryFlow() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val pending = async { assertFailsWith<LinkClientException.SessionClosed> { client.snapshot() } }
                channel.request() as LinkMessage.SnapshotGet
                client.close()
                pending.await()
                assertEquals(emptyList(), client.changes.toList())
                assertEquals(emptyList(), client.sessionChanges.toList())
                assertEquals(emptyList(), client.workspaceChanges.toList())
                assertEquals(emptyList(), client.chatEntries.toList())
                assertFailsWith<LinkClientException.SessionClosed> { client.snapshot() }
                assertFailsWith<RelayException.Closed> { channel.receive() }
                client.close() // idempotent
            }
        }
    }

    @Test
    fun hostClosingEndsTheSession() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val pending = async { assertFailsWith<LinkClientException.SessionClosed> { client.snapshot() } }
                channel.request() as LinkMessage.SnapshotGet
                channel.close()
                pending.await()
                assertEquals(emptyList(), client.changes.toList())
                assertFailsWith<LinkClientException.SessionClosed> { client.sessions() }
            }
        }
    }

    @Test
    fun cancelledCallerLeavesTheSessionUsable() {
        runBlocking {
            within {
                val rig = HostRig(wrapClient = ::SuspendingSendCircuit)
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                // Cancelled while it waits for the answer.
                val job = launch { client.snapshot() }
                val cancelled = channel.request() as LinkMessage.SnapshotGet
                job.cancelAndJoin()
                assertEquals(0, client.pendingCalls)
                channel.send(LinkMessage.Snapshot(cancelled.callId, 1, emptyList()))
                // Cancelled while its encrypted frame is suspended in the circuit's send: the frame still goes out.
                val midSend = launch(start = CoroutineStart.UNDISPATCHED) { client.snapshot() }
                midSend.cancelAndJoin()
                assertEquals(0, client.pendingCalls)
                val next = async { client.snapshot() }
                val sentAnyway = channel.request() as LinkMessage.SnapshotGet
                channel.send(LinkMessage.Snapshot(sentAnyway.callId, 2, emptyList()))
                val get = channel.request() as LinkMessage.SnapshotGet
                assertEquals(3, setOf(cancelled.callId, sentAnyway.callId, get.callId).size)
                channel.send(LinkMessage.Snapshot(get.callId, 5, emptyList()))
                // Both late answers were dropped.
                assertEquals(5, next.await().revision)
                client.close()
            }
        }
    }

    @Test
    fun cancellingManyCallersNeverBreaksTheCipherStream() {
        runBlocking {
            within(10.seconds) {
                // The client's sends suspend before they reach the circuit, so a cancellation can land after a frame
                // was encrypted (Review Focus 1); the in-memory pair alone never suspends in send.
                val rig = HostRig(wrapClient = ::SuspendingSendCircuit)
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val hostErrors = CopyOnWriteArrayList<Throwable>()
                val served = async {
                    var replies = 0
                    while (true) {
                        val message = try {
                            channel.receive()
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            hostErrors += e
                            channel.close()
                            break
                        }
                        when (message) {
                            is LinkMessage.Reply -> {
                                replies += 1
                                channel.send(LinkMessage.ReplyResult(message.callId, message.requestId, ReplyOutcome.DELIVERED))
                            }
                            is LinkMessage.SnapshotGet -> {
                                channel.send(LinkMessage.Snapshot(message.callId, 5, emptyList()))
                                break
                            }
                            else -> Unit
                        }
                    }
                    replies
                }

                /** The call's outcome, or the failure it threw; cancellation propagates. */
                suspend fun attempt(block: suspend () -> ReplyOutcome): Any = try {
                    block()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    e
                }

                // Deterministic: each caller takes the free send lock, encrypts its reply and suspends in the
                // circuit's send; every odd one is cancelled right there.
                val sequential = (0 until 20).map { i ->
                    val caller = async(start = CoroutineStart.UNDISPATCHED) { attempt { client.reply("s$i", once) } }
                    if (i % 2 == 1) caller.cancel()
                    caller.join()
                    caller
                }
                // Concurrent: 100 callers on Dispatchers.Default, every odd one cancelled at once.
                val jobs = (0 until 100).map { i ->
                    async(Dispatchers.Default, start = CoroutineStart.UNDISPATCHED) { attempt { client.reply("r$i", once) } }
                }
                jobs.forEachIndexed { i, job -> if (i % 2 == 1) job.cancel() }
                jobs.joinAll()
                assertEquals(emptyList(), hostErrors.map { it::class.simpleName }, "the host could not decrypt a frame")
                val kept = (sequential.filterIndexed { i, _ -> i % 2 == 0 } + jobs.filterIndexed { i, _ -> i % 2 == 0 }).awaitAll()
                assertTrue(kept.all { it == ReplyOutcome.DELIVERED }, "$kept")
                assertEquals(5, client.snapshot().revision)
                val replies = served.await()
                assertEquals(emptyList(), hostErrors.map { it::class.simpleName })
                // All 20 sequential replies were sent (a cancellation landed after encryption), and 50 to 100 others.
                assertTrue(replies in 70..120, "replies: $replies")
                assertEquals(0, client.pendingCalls)
                client.close()
            }
        }
    }

    @Test
    fun silentHostIsClosedByTheWatchdog() {
        runBlocking {
            within {
                val rig = HostRig(timings = LinkTimings(50.milliseconds, 300.milliseconds, requestTimeout = 5.seconds))
                val host = async { rig.host() }
                val client = rig.client()
                host.await()
                val started = TimeSource.Monotonic.markNow()
                assertFailsWith<LinkClientException.SessionClosed> { client.snapshot() }
                val elapsed = started.elapsedNow()
                assertTrue(elapsed >= 250.milliseconds && elapsed < 3.seconds, "closed after $elapsed")
                assertEquals(emptyList(), client.changes.toList())
                assertEquals(emptyList(), client.sessionChanges.toList())
                assertEquals(emptyList(), client.workspaceChanges.toList())
                assertEquals(emptyList(), client.chatEntries.toList())
            }
        }
    }

    /** The client half of Swift's `testPingsKeepIdleSessionAlive`: frames from a live host keep the watchdog away. */
    @Test
    fun hostPingsKeepALiveSessionPastIdleTimeout() {
        runBlocking {
            within {
                val rig = HostRig(timings = LinkTimings(50.milliseconds, 300.milliseconds, requestTimeout = 5.seconds))
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val hostPings = launch {
                    var nonce = 0uL
                    try {
                        while (true) {
                            delay(50.milliseconds)
                            channel.send(LinkMessage.Ping(nonce++))
                        }
                    } catch (_: RelayException.Closed) {
                        // The session ended; the assertions below report it.
                    }
                }
                // More than three idle timeouts with nothing but pings.
                delay(1.seconds)
                val snapshot = async { client.snapshot() }
                while (true) {
                    val message = channel.receive()
                    if (message is LinkMessage.SnapshotGet) {
                        channel.send(LinkMessage.Snapshot(message.callId, 9, emptyList()))
                        break
                    }
                }
                assertEquals(9, snapshot.await().revision)
                hostPings.cancelAndJoin()
                client.close()
            }
        }
    }

    @Test
    fun silentHandshakeIsClosedByTheWatchdog() {
        runBlocking {
            within {
                val rig = HostRig(timings = LinkTimings(50.milliseconds, 200.milliseconds))
                assertFailsWith<RelayException.Closed> { rig.client() }
            }
        }
    }

    @Test
    fun logCarriesEventNamesAndCodesOnly() {
        runBlocking {
            within {
                val secret = "secret-xyz"
                val events = CopyOnWriteArrayList<String>()
                val previous = LinkLog.sink
                LinkLog.sink = { events += it }
                try {
                    val rig = HostRig()
                    val host = async { rig.host() }
                    val client = rig.client()
                    val (channel, _) = host.await()
                    channel.send(Error("bad_request", secret))
                    channel.sendFrame("""{"v":1,"t":"agent.changed","revision":1,"x":"$secret"}""".encodeToByteArray())
                    channel.send(LinkMessage.Changed(1, emptyList(), emptyList()))
                    client.changes.first()
                    client.close()
                    assertEquals(listOf("host reported error bad_request", "client dropped an undecodable frame"), events.toList())
                } finally {
                    LinkLog.sink = previous
                }
            }
        }
    }

    @Test
    fun sessionTypesNeverPrintContent() {
        val s = "secret-xyz"
        val item = item.copy(workspaceTitle = s)
        val session = session.copy(title = s)
        val entry = entry.copy(text = s)
        val workspace = workspace.copy(title = s)
        val values: List<Any> = listOf(
            PendingSnapshot(1, listOf(item)), PendingChange(1, listOf(item), listOf("r0")),
            SessionList(1, listOf(session)), SessionChange(1, listOf(session), emptyList()),
            WorkspaceList(1, listOf(workspace)), WorkspaceChange(1, listOf(workspace), emptyList()),
            ChatHistoryPage(listOf(entry), hasMore = true), ChatPush.Upsert("s-1", listOf(entry)),
            ProtocolMismatch(s), LinkClientException.Rejected("bad_request", s), LinkClientException.Remote("not_found", s),
        )
        for (value in values) {
            val text = value.toString()
            assertFalse(s in text, "${value::class.simpleName} printed content: $text".replace(s, "<sentinel>"))
            assertTrue("<redacted>" in text, "${value::class.simpleName} redacts nothing: $text")
        }
        for (error in listOf(ProtocolMismatch(s), LinkClientException.Rejected("c", s), LinkClientException.Remote("c", s))) {
            assertFalse(s in error.message.orEmpty())
        }
        assertTrue("code=not_found" in LinkClientException.Remote("not_found", s).toString())
        assertEquals("session_closed", LinkClientException.SessionClosed().message)
        assertEquals("timed_out", LinkClientException.TimedOut().message)
        assertEquals("unexpected_answer", LinkClientException.UnexpectedAnswer().message)
        assertEquals(LinkTimings(20.seconds, 45.seconds, 10.seconds), LinkTimings.STANDARD)
    }
}
