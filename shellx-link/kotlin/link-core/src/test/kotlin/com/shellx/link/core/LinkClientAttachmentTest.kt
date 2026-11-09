package com.shellx.link.core

import java.util.concurrent.CopyOnWriteArrayList
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class LinkClientAttachmentTest {
    private val file = AttachmentKind.FILE

    /** A connected client and a [FakeAttachHost] serving it on a host that lists `attachments`. */
    private class Rig(val client: LinkClient, val host: FakeAttachHost)

    private suspend fun CoroutineScope.connect(stall: Boolean = false, answerChatSend: Boolean = true): Rig {
        val rig = HostRig(features = listOf(ShellXLink.ATTACHMENTS_FEATURE))
        val host = async { rig.host() }
        val client = rig.client()
        val fake = FakeAttachHost(host.await().first, stall, answerChatSend)
        launch { fake.serve() }
        assertTrue(ShellXLink.ATTACHMENTS_FEATURE in client.hostFeatures)
        return Rig(client, fake)
    }

    private fun bytes(count: Int, f: (Int) -> Int = { it % 251 }) = ByteArray(count) { f(it).toByte() }

    @Test
    fun uploadSendsChunksInOrderWithTheDigest() {
        runBlocking {
            within {
                val (client, host) = connect().let { it.client to it.host }
                val data = bytes(100_000)
                val progress = CopyOnWriteArrayList<Int>()
                assertEquals("U1", client.uploadAttachment(file, "data.bin", data) { progress += it })
                assertEquals(
                    listOf(Triple("U1", 0, 45_000), Triple("U1", 45_000, 45_000), Triple("U1", 90_000, 10_000)),
                    host.chunks.toList(),
                )
                assertContentEquals(sha256(data), host.digests.single())
                assertEquals(listOf(45_000, 90_000, 100_000), progress.toList())
                assertEquals(listOf("begin:U1", "chunk:U1:0", "chunk:U1:45000", "chunk:U1:90000", "end:U1"), host.events.toList())
                // The host holds exactly the bytes.
                assertEquals(ChatSendOutcome.SUBMITTED, client.chatSend("s1", "here", listOf("U1")))
                assertContentEquals(data, host.sent.single().bytes.single())
                client.close()
            }
        }
    }

    @Test
    fun uploadsRunOneAtATime() {
        runBlocking {
            within {
                val (client, host) = connect().let { it.client to it.host }
                val a = async { client.uploadAttachment(file, "a", bytes(100_000)) }
                assertTrue(eventually { "begin:U1" in host.events })
                val b = async { client.uploadAttachment(AttachmentKind.IMAGE, "b.jpg", bytes(50_000) { it * 7 % 253 }) }
                assertEquals(listOf("U1", "U2"), listOf(a.await(), b.await()))
                val events = host.events.toList()
                val beginB = events.indexOf("begin:U2")
                assertTrue(events.indexOf("end:U1") in 0 until beginB, "$events")
                assertTrue(events.withIndex().filter { "U1" in it.value }.all { it.index < beginB }, "$events")
                assertEquals(ChatSendOutcome.SUBMITTED, client.chatSend("s1", "both", listOf("U1", "U2")))
                assertEquals(listOf("a", "b.jpg"), host.sent.single().names)
                client.close()
            }
        }
    }

    @Test
    fun cancelledUploadReleasesTheTurn() {
        runBlocking {
            within {
                val (client, host) = connect(stall = true).let { it.client to it.host }
                val progress = CopyOnWriteArrayList<Int>()
                val a = async { client.uploadAttachment(file, "a", bytes(100_000)) { progress += it } }
                // A holds the turn and waits for the answer to its second chunk, which never comes.
                assertTrue(eventually { progress == listOf(45_000) })
                val b = async { client.uploadAttachment(file, "b", byteArrayOf(1, 2, 3)) }
                assertTrue(eventually { client.uploadsWaiting == 1 })
                delay(200.milliseconds)
                assertFalse("begin:U2" in host.events)
                a.cancelAndJoin()
                assertFailsWith<CancellationException> { a.await() }
                assertEquals("U2", b.await())
                client.close()
            }
        }
    }

    @Test
    fun cancelledWaiterLeavesTheQueue() {
        runBlocking {
            within {
                val (client, host) = connect(stall = true).let { it.client to it.host }
                val progress = CopyOnWriteArrayList<Int>()
                val a = async { client.uploadAttachment(file, "a", bytes(100_000)) { progress += it } }
                assertTrue(eventually { progress == listOf(45_000) })
                val b = async { client.uploadAttachment(file, "b", byteArrayOf(1)) }
                assertTrue(eventually { client.uploadsWaiting == 1 })
                val c = async { client.uploadAttachment(file, "c", byteArrayOf(2)) }
                assertTrue(eventually { client.uploadsWaiting == 2 })
                // A waiter that gives up leaves the queue at once, and the turn skips it.
                b.cancelAndJoin()
                assertFailsWith<CancellationException> { b.await() }
                assertTrue(eventually { client.uploadsWaiting == 1 })
                a.cancelAndJoin()
                assertEquals("U2", c.await())
                assertEquals(listOf("begin:U1", "begin:U2"), host.events.filter { it.startsWith("begin:") })
                client.close()
            }
        }
    }

    @Test
    fun failedUploadReleasesTheTurn() {
        runBlocking {
            within {
                val client = connect().client
                // Undispatched, so the refused upload takes the turn first.
                val refused = async(start = CoroutineStart.UNDISPATCHED) {
                    assertFailsWith<LinkClientException.Remote> {
                        client.uploadAttachment(file, "big", ByteArray(ShellXLink.MAX_ATTACHMENT_BYTES + 1))
                    }
                }
                val fine = async { client.uploadAttachment(file, "ok", byteArrayOf(1, 2)) }
                assertEquals("too_large", refused.await().code)
                // `n` counts accepted begins, and the refused begin was not accepted.
                assertEquals("U1", fine.await())
                assertEquals(ChatSendOutcome.SUBMITTED, client.chatSend("s1", "", listOf("U1")))
                client.close()
            }
        }
    }

    @Test
    fun messageHoldsTheTurnUntilItsSendIsAnswered() {
        runBlocking {
            within {
                val (client, host) = connect(answerChatSend = false).let { it.client to it.host }
                val message = async { client.chatSend("s1", "look", listOf(ChatAttachment(file, "a", byteArrayOf(1)))) }
                // Its upload is done, and its chat.send, which this host never answers, has arrived.
                assertTrue(eventually { "send:look" in host.events })
                val other = async { client.uploadAttachment(file, "b", byteArrayOf(2)) }
                assertTrue(eventually { client.uploadsWaiting == 1 })
                delay(200.milliseconds)
                assertEquals(listOf("begin:U1"), host.events.filter { it.startsWith("begin:") })
                message.cancelAndJoin()
                // Cancellation propagates as it is, never wrapped in MessageUploadException.
                assertFailsWith<CancellationException> { message.await() }
                assertEquals("U2", other.await())
                client.close()
            }
        }
    }

    @Test
    fun messageReportsProgressAndStopsAtARefusedUpload() {
        runBlocking {
            within {
                val (client, host) = connect().let { it.client to it.host }
                val progress = CopyOnWriteArrayList<Int>()
                val outcome = client.chatSend(
                    "s1", "both",
                    listOf(ChatAttachment(file, "big", ByteArray(100_000)), ChatAttachment(AttachmentKind.IMAGE, "small.jpg", byteArrayOf(1, 2, 3))),
                ) { progress += it }
                assertEquals(ChatSendOutcome.SUBMITTED, outcome)
                assertEquals(listOf(45_000, 90_000, 100_000, 100_003), progress.toList())
                assertEquals(listOf("big", "small.jpg"), host.sent.single().names)
                assertEquals("send:both", host.events.last())

                val error = assertFailsWith<MessageUploadException> {
                    client.chatSend(
                        "s1", "x", listOf(ChatAttachment(file, "fine", byteArrayOf(1)), ChatAttachment(file, "empty", ByteArray(0))),
                    )
                }
                assertEquals("bad_request", assertIs<LinkClientException.Remote>(error.cause).code)
                assertEquals(1, host.sent.size, "the refused message was sent")
                assertFalse("send:x" in host.events)
                client.close()
            }
        }
    }

    @Test
    fun twoMessagesOfFiveAttachmentsBothArriveWhole() {
        runBlocking {
            within(10.seconds) {
                val (client, host) = connect().let { it.client to it.host }
                fun five(prefix: String) =
                    (0 until ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE).map { ChatAttachment(file, "$prefix$it", ByteArray(50_000)) }
                val one = async { client.chatSend("s1", "one", five("a")) }
                val two = async { client.chatSend("s1", "two", five("b")) }
                assertEquals(listOf(ChatSendOutcome.SUBMITTED, ChatSendOutcome.SUBMITTED), listOf(one.await(), two.await()))
                val byText = host.sent.associate { it.text to it.names }
                assertEquals(listOf("a0", "a1", "a2", "a3", "a4"), byText["one"])
                assertEquals(listOf("b0", "b1", "b2", "b3", "b4"), byText["two"])
                client.close()
            }
        }
    }

    @Test
    fun closingWithQueuedUploadsFailsThemAll() {
        runBlocking {
            within {
                val client = connect(stall = true).client
                val progress = CopyOnWriteArrayList<Int>()
                val a = async {
                    assertFailsWith<LinkClientException.SessionClosed> {
                        client.uploadAttachment(file, "a", bytes(100_000)) { progress += it }
                    }
                }
                assertTrue(eventually { progress == listOf(45_000) })
                val b = async { assertFailsWith<LinkClientException.SessionClosed> { client.uploadAttachment(file, "b", byteArrayOf(1)) } }
                assertTrue(eventually { client.uploadsWaiting == 1 })
                val m = async {
                    assertFailsWith<MessageUploadException> {
                        client.chatSend("s1", "m", listOf(ChatAttachment(file, "c", byteArrayOf(2))))
                    }
                }
                assertTrue(eventually { client.uploadsWaiting == 2 })
                client.close()
                within(2.seconds) {
                    a.await()
                    b.await()
                    assertIs<LinkClientException.SessionClosed>(m.await().cause)
                }
                // Later uploads fail at once the same way.
                assertFailsWith<LinkClientException.SessionClosed> { client.uploadAttachment(file, "d", byteArrayOf(3)) }
                val late = assertFailsWith<MessageUploadException> {
                    client.chatSend("s1", "n", listOf(ChatAttachment(file, "e", byteArrayOf(4))))
                }
                assertIs<LinkClientException.SessionClosed>(late.cause)
            }
        }
    }

    @Test
    fun hostWithoutTheFeatureAnswersUnsupported() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                assertFalse(ShellXLink.ATTACHMENTS_FEATURE in client.hostFeatures)
                val upload = async {
                    assertFailsWith<LinkClientException.Remote> { client.uploadAttachment(file, "a", byteArrayOf(1)) }
                }
                val begin = channel.request() as LinkMessage.AttachBegin
                channel.send(LinkMessage.Error("unsupported", "this host takes no attachments", begin.callId))
                assertEquals("unsupported", upload.await().code)
                client.close()
            }
        }
    }

    @Test
    fun wrongChunkAnswerIsUnexpectedAnswer() {
        runBlocking {
            within {
                val rig = HostRig()
                val host = async { rig.host() }
                val client = rig.client()
                val (channel, _) = host.await()
                val upload = async {
                    assertFailsWith<LinkClientException.UnexpectedAnswer> { client.uploadAttachment(file, "a", byteArrayOf(1, 2)) }
                }
                val begin = channel.request() as LinkMessage.AttachBegin
                channel.send(LinkMessage.AttachReady(begin.callId, "x1"))
                val chunk = channel.request() as LinkMessage.AttachChunk
                // One byte short of what was sent.
                channel.send(LinkMessage.AttachChunkResult(chunk.callId, "x1", 1))
                upload.await()
                client.close()
            }
        }
    }

    @Test
    fun attachmentTypesNeverPrintContent() {
        val s = "secret-xyz"
        val attachment = ChatAttachment(AttachmentKind.IMAGE, s, s.encodeToByteArray())
        val text = attachment.toString()
        assertFalse(s in text, text.replace(s, "<sentinel>"))
        assertTrue("<redacted>" in text && "<10 bytes>" in text && "kind=" in text, text)
        assertEquals(attachment, ChatAttachment(AttachmentKind.IMAGE, s, s.encodeToByteArray()))
        assertEquals(attachment.hashCode(), ChatAttachment(AttachmentKind.IMAGE, s, s.encodeToByteArray()).hashCode())
        assertNotEquals(attachment, ChatAttachment(AttachmentKind.IMAGE, s, byteArrayOf(1)))
        val error = MessageUploadException(LinkClientException.Remote("bad_request", s))
        assertEquals("message_upload", error.message)
        assertFalse(s in error.toString())
    }
}
