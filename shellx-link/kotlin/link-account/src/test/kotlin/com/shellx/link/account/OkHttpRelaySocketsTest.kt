package com.shellx.link.account

import com.shellx.link.core.RelayException
import com.shellx.link.core.RelaySocketMessage
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.junit.jupiter.api.Test

class OkHttpRelaySocketsTest {
    /** The server end of one upgraded socket. */
    private class ServerSide(private val onOpen: (WebSocket) -> Unit = {}) : WebSocketListener() {
        val texts = Channel<String>(Channel.UNLIMITED)
        val binaries = Channel<ByteArray>(Channel.UNLIMITED)

        /** How the socket ended for the server: `closing <code>` or `failure`. */
        val ended = CompletableDeferred<String>()

        override fun onOpen(webSocket: WebSocket, response: okhttp3.Response) = onOpen(webSocket)

        override fun onMessage(webSocket: WebSocket, text: String) {
            texts.trySend(text)
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            binaries.trySend(bytes.toByteArray())
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            ended.complete("closing $code")
            webSocket.close(1000, null)
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: okhttp3.Response?) {
            ended.complete("failure")
        }
    }

    private class Rig : AutoCloseable {
        val server = MockWebServer().apply { start(InetAddress.getByName("127.0.0.1"), 0) }
        val client = OkHttpClient()
        val sockets = OkHttpRelaySockets(client)
        val url: URI = URI("ws://127.0.0.1:${server.port}/v1/relay")

        fun upgrade(side: ServerSide): ServerSide {
            server.enqueue(MockResponse.Builder().webSocketUpgrade(side).build())
            return side
        }

        override fun close() {
            server.close()
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }

    @Test
    fun deliversTextAndBinaryWithTheBearer() {
        runBlocking {
            Rig().use { rig ->
                rig.upgrade(ServerSide { it.send("hello"); it.send(byteArrayOf(1, 2, 3).toByteString()) })
                val socket = rig.sockets.open(rig.url, bearer = "t1")
                within {
                    assertEquals(RelaySocketMessage.Text("hello"), socket.receive())
                    assertEquals(RelaySocketMessage.Binary(byteArrayOf(1, 2, 3)), socket.receive())
                }
                val upgrade = rig.server.takeRequest(5, TimeUnit.SECONDS)!!
                assertEquals("Bearer t1", upgrade.headers["Authorization"])
                assertEquals("/v1/relay", upgrade.url.encodedPath)
                socket.close()
            }
        }
    }

    @Test
    fun sendsReachTheServer() {
        runBlocking {
            Rig().use { rig ->
                val side = rig.upgrade(ServerSide())
                val socket = rig.sockets.open(rig.url, bearer = null)
                socket.sendText("x")
                socket.sendBinary(byteArrayOf(9))
                within {
                    assertEquals("x", side.texts.receive())
                    assertContentEquals(byteArrayOf(9), side.binaries.receive())
                }
                assertNull(rig.server.takeRequest(5, TimeUnit.SECONDS)!!.headers["Authorization"])
                socket.close()
            }
        }
    }

    @Test
    fun serverCloseIsClosed() {
        runBlocking {
            Rig().use { rig ->
                rig.upgrade(ServerSide { it.send("last"); it.close(1000, "bye") })
                val socket = rig.sockets.open(rig.url, bearer = "t1")
                within {
                    // What arrived before the close is still delivered.
                    assertEquals(RelaySocketMessage.Text("last"), socket.receive())
                    assertFailsWith<RelayException.Closed> { socket.receive() }
                }
                assertFailsWith<RelayException.Closed> { socket.sendText("x") }
                assertFailsWith<RelayException.Closed> { socket.sendBinary(byteArrayOf(1)) }
            }
        }
    }

    @Test
    fun failureBeforeOpenIsIOException() {
        runBlocking {
            val closedPort = ServerSocket(0).use { it.localPort }
            Rig().use { rig ->
                val socket = rig.sockets.open(URI("ws://127.0.0.1:$closedPort/v1/relay"), bearer = "t1")
                within { assertFailsWith<IOException> { socket.receive() } }
                assertFailsWith<RelayException.Closed> { socket.sendText("x") }

                // A refused upgrade is a failure too.
                rig.server.enqueue(MockResponse.Builder().code(401).build())
                val refused = rig.sockets.open(rig.url, bearer = "t1")
                within { assertFailsWith<IOException> { refused.receive() } }
            }
        }
    }

    @Test
    fun cancellingAPendingReceiveCancelsTheSocket() {
        runBlocking {
            Rig().use { rig ->
                val side = rig.upgrade(ServerSide { it.send("open") })
                val socket = rig.sockets.open(rig.url, bearer = "t1")
                within { assertEquals(RelaySocketMessage.Text("open"), socket.receive()) }
                val pending = async(Dispatchers.Default, start = CoroutineStart.UNDISPATCHED) { socket.receive() }
                pending.cancel()
                within { pending.join() }
                assertTrue(pending.isCancelled)
                // Closed at once, not only after OkHttp's reader thread has noticed the cancelled call.
                assertFailsWith<RelayException.Closed> { socket.sendText("x") }
                assertFailsWith<RelayException.Closed> { socket.sendBinary(byteArrayOf(1)) }
                within { assertFailsWith<RelayException.Closed> { socket.receive() } }
                assertEquals("failure", within { side.ended.await() })
                assertFailsWith<RelayException.Closed> { socket.sendText("x") }
            }
        }
    }

    @Test
    fun closeEndsAPendingReceiveAndIsIdempotent() {
        runBlocking {
            Rig().use { rig ->
                val side = rig.upgrade(ServerSide { it.send("open") })
                val socket = rig.sockets.open(rig.url, bearer = "t1")
                within { assertEquals(RelaySocketMessage.Text("open"), socket.receive()) }
                val pending = async(Dispatchers.Default, start = CoroutineStart.UNDISPATCHED) {
                    assertFailsWith<RelayException.Closed> { socket.receive() }
                }
                socket.close()
                socket.close()
                within {
                    pending.await()
                    assertEquals("closing 1000", side.ended.await())
                }
                assertFailsWith<RelayException.Closed> { socket.sendText("x") }
            }
        }
    }

    @Test
    fun idleSocketOutlivesTheClientReadTimeout() {
        runBlocking {
            Rig().use { rig ->
                // RelayApi hands its 15 s read timeout to its sockets; an idle circuit must not die of it.
                val sockets = OkHttpRelaySockets(rig.client.newBuilder().readTimeout(200, TimeUnit.MILLISECONDS).build())
                val opened = CompletableDeferred<WebSocket>()
                rig.upgrade(ServerSide { opened.complete(it) })
                val socket = sockets.open(rig.url, bearer = "t1")
                val pending = async(Dispatchers.Default) { socket.receive() }
                val server = within { opened.await() }
                delay(800)
                server.send("later")
                assertEquals(RelaySocketMessage.Text("later"), within { pending.await() })
                socket.close()
            }
        }
    }

    /** Polls [condition] every 5 ms for at most 5 s. */
    private suspend fun eventually(condition: () -> Boolean): Boolean {
        repeat(1000) {
            if (condition()) return true
            delay(5)
        }
        return condition()
    }

    /** Whether some thread waits for room in a socket's inbox (OkHttp's reader thread, held by the bound). */
    private fun aReaderWaitsForRoom(): Boolean =
        Thread.getAllStackTraces().values.any { trace -> trace.any { it.className.endsWith("InboxBudget") && it.methodName == "take" } }

    @Test
    fun anUnreadFloodIsBoundedAndNothingBehindItIsLost() {
        runBlocking {
            Rig().use { rig ->
                val chunk = 60_000
                val count = 200
                rig.upgrade(ServerSide { ws ->
                    for (i in 0 until count) ws.send(ByteArray(chunk) { i.toByte() }.toByteString())
                    ws.send("reply")
                })
                val socket = rig.sockets.open(rig.url, bearer = "t1") as OkHttpRelaySocket
                // Nobody reads: OkHttp's reader thread stops at the bound, and TCP holds back the rest.
                assertTrue(eventually { socket.queuedBytes > OkHttpRelaySocket.MAX_QUEUED_BYTES - chunk }, "${socket.queuedBytes}")
                assertTrue(eventually(::aReaderWaitsForRoom))
                delay(300)
                assertTrue(socket.queuedBytes <= OkHttpRelaySocket.MAX_QUEUED_BYTES, "${socket.queuedBytes}")
                within {
                    for (i in 0 until count) {
                        val bytes = (socket.receive() as RelaySocketMessage.Binary).bytes
                        assertEquals(chunk, bytes.size)
                        assertEquals(i.toByte(), bytes.first(), "message $i")
                        assertEquals(i.toByte(), bytes.last(), "message $i")
                    }
                    assertEquals(RelaySocketMessage.Text("reply"), socket.receive())
                }
                assertEquals(0, socket.queuedBytes)
                socket.close()
            }
        }
    }

    @Test
    fun closeFreesAReaderThatWaitsForRoom() {
        runBlocking {
            Rig().use { rig ->
                rig.upgrade(ServerSide { ws -> repeat(100) { ws.send(ByteArray(60_000).toByteString()) } })
                val socket = rig.sockets.open(rig.url, bearer = "t1") as OkHttpRelaySocket
                assertTrue(eventually(::aReaderWaitsForRoom))
                socket.close()
                assertTrue(eventually { !aReaderWaitsForRoom() })
                assertFailsWith<RelayException.Closed> { socket.sendText("x") }
            }
        }
    }

    @Test
    fun plainSocketToARemoteHostIsRefused() {
        Rig().use { rig ->
            assertEquals(
                RelayException.InsecureTransport("ws"),
                assertFailsWith<RelayException.InsecureTransport> { rig.sockets.open(URI("ws://relay.example.test/v1/relay"), "t1") },
            )
            for (bad in listOf("ftp://127.0.0.1/v1/relay", "ws://127.+0.0.1:1/v1/relay", "ws:///v1/relay")) {
                assertFailsWith<RelayException.ProtocolViolation>(bad) { rig.sockets.open(URI(bad), "t1") }
            }
            assertEquals(0, rig.server.requestCount)
        }
    }
}
