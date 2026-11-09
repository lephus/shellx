package com.shellx.link.account

import com.shellx.link.core.LinkMessage
import com.shellx.link.core.NoiseRole
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.RelayControl
import com.shellx.link.core.SecureChannel
import com.shellx.link.core.inMemoryCircuitPair
import java.net.InetAddress
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.OkHttpClient
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString

/**
 * The ShellX API and a relay on one MockWebServer at 127.0.0.1:
 * - `POST /v2/relay/tickets` mints a stub ticket for [mintedSlot] on this server's `ws://…/v2/relay`;
 * - an upgrade of `GET /v2/relay` answers `connect` with `allocated` (circuit `c-1`, join ticket `jt-1`), and `join`
 *   with `ready`, then bridges binary frames to an in-memory circuit whose other end runs the host.
 */
class FakeWebSocketRelay(@Volatile var mintedSlot: String = "slot-1") : AutoCloseable {
    val server = MockWebServer()
    val client = OkHttpClient()
    val ticketBodies = CopyOnWriteArrayList<JsonObject>()

    /** When set, the ticket route answers this status and error code instead of a ticket. */
    @Volatile var refuseTickets: Pair<Int, String>? = null

    /** The `Authorization` header of each upgrade, in order. */
    val upgradeAuthorizations = CopyOnWriteArrayList<String?>()

    /** Every text message the relay received, in order. */
    val texts = CopyOnWriteArrayList<String>()

    private val circuit = inMemoryCircuitPair()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    init {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.url.encodedPath
                return when {
                    request.method == "POST" && path == "/v2/relay/tickets" -> {
                        ticketBodies += request.json()
                        val refused = refuseTickets
                        if (refused != null) {
                            return MockResponse.Builder().code(refused.first).addHeader("Content-Type", "application/json")
                                .body("""{"error":{"code":"${refused.second}","message":"x"}}""").build()
                        }
                        MockResponse.Builder().code(200).addHeader("Content-Type", "application/json").body(
                            """{"ticket":"${stubTicket(mintedSlot)}","expires_at_unix":1900000000,""" +
                                """"relay_url":"ws://127.0.0.1:${server.port}/v2/relay"}""",
                        ).build()
                    }
                    request.method == "GET" && path == "/v2/relay" -> {
                        upgradeAuthorizations += request.headers["Authorization"]
                        MockResponse.Builder().webSocketUpgrade(RelayListener()).build()
                    }
                    else -> MockResponse.Builder().code(404).build()
                }
            }
        }
        server.start(InetAddress.getByName("127.0.0.1"), 0)
    }

    val base: String get() = "http://127.0.0.1:${server.port}"

    fun api(clientVersion: String = "1.0.0"): RelayApi = RelayApi(base, client, clientVersion)

    /**
     * Runs a host on the far end of the circuit: a responder handshake trusting any client, then it reads `hello` and
     * answers `welcome` with the `workspaces` feature. The result is the `hello`, or null when the handshake failed.
     */
    fun startHost(key: NoiseStaticKey): Deferred<LinkMessage.Hello?> = scope.async {
        try {
            val channel = SecureChannel.open(circuit.second, NoiseRole.RESPONDER, key) { true }
            val hello = channel.receive() as LinkMessage.Hello
            channel.send(LinkMessage.Welcome(1, "test-host", "Test Mac", listOf("workspaces")))
            hello
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    override fun close() {
        scope.cancel()
        circuit.first.close()
        server.close()
        client.dispatcher.executorService.shutdown()
        client.connectionPool.evictAll()
    }

    private inner class RelayListener : WebSocketListener() {
        private val toHost = Channel<ByteArray>(Channel.UNLIMITED)

        override fun onMessage(webSocket: WebSocket, text: String) {
            texts += text
            when (val control = RelayControl.decode(text)) {
                is RelayControl.Connect ->
                    webSocket.send(RelayControl.Allocated("c-1", control.lane, control.generation, "jt-1").encodeText())
                is RelayControl.Join -> {
                    webSocket.send(RelayControl.Ready(control.circuit, control.lane, control.generation).encodeText())
                    bridge(webSocket)
                }
                else -> Unit
            }
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            toHost.trySend(bytes.toByteArray())
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(1000, null)
            toHost.close()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: okhttp3.Response?) {
            toHost.close()
        }

        private fun bridge(webSocket: WebSocket) {
            scope.launch {
                try {
                    for (frame in toHost) circuit.first.send(frame)
                } finally {
                    circuit.first.close()
                }
            }
            scope.launch {
                try {
                    while (true) webSocket.send(circuit.first.receive().toByteString())
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    webSocket.close(1000, null)
                }
            }
        }
    }
}
