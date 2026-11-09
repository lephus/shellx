package com.shellx.link.account

import com.shellx.link.core.RelayException
import com.shellx.link.core.RelaySocket
import com.shellx.link.core.RelaySocketFactory
import com.shellx.link.core.RelaySocketMessage
import com.shellx.link.core.RelayTransportPolicy
import java.io.IOException
import java.net.URI
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ClosedReceiveChannelException
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString

/**
 * Relay sockets over OkHttp WebSockets. Redirects are never followed. `wss` (or `https`) goes anywhere; `ws` (or
 * `http`) only to a loopback host ([RelayException.InsecureTransport] otherwise), checked on the host `java.net.URI`
 * parses and that OkHttp then connects to. Any other URL is [RelayException.ProtocolViolation].
 */
class OkHttpRelaySockets(client: OkHttpClient) : RelaySocketFactory {
    private val client = client.newBuilder().followRedirects(false).followSslRedirects(false).build()

    override fun open(url: URI, bearer: String?): RelaySocket {
        val scheme = url.scheme?.lowercase()
        if (url.host == null) throw RelayException.ProtocolViolation("relay URL is invalid")
        when (scheme) {
            "wss", "https" -> Unit
            "ws", "http" -> if (!RelayTransportPolicy.isLoopback(url.host)) throw RelayException.InsecureTransport(scheme)
            else -> throw RelayException.ProtocolViolation("relay URL is invalid")
        }
        val request = Request.Builder()
            .url(url.toCheckedHttpUrl())
            .apply { if (bearer != null) header("Authorization", "Bearer $bearer") }
            .build()
        return OkHttpRelaySocket(client, request)
    }
}

/**
 * One OkHttp WebSocket. Incoming messages queue without bound (plan 3B): OkHttp's reader thread always drains the
 * socket into the queue, so the relay's own queue limit never engages and only the phone's memory bounds it. That is
 * fine for today's answers and small pushes. Terminal output streams (plan 3G) need a bound: block the reader on a
 * bounded queue (which restores TCP back-pressure), or cap the queued bytes and close the socket.
 */
private class OkHttpRelaySocket(client: OkHttpClient, request: Request) : RelaySocket {
    private val inbox = Channel<RelaySocketMessage>(Channel.UNLIMITED)
    private val webSocket: WebSocket = client.newWebSocket(request, Listener())

    /**
     * Set by a local close or cancel. OkHttp only refuses sends once its reader thread has seen a cancelled call, so a
     * send right after a cancel would otherwise be accepted and lost.
     */
    @Volatile private var closedHere = false

    override suspend fun sendText(text: String) {
        if (closedHere || !webSocket.send(text)) throw RelayException.Closed()
    }

    override suspend fun sendBinary(bytes: ByteArray) {
        if (closedHere || !webSocket.send(bytes.toByteString())) throw RelayException.Closed()
    }

    override suspend fun receive(): RelaySocketMessage = try {
        inbox.receive()
    } catch (_: ClosedReceiveChannelException) {
        throw RelayException.Closed()
    } catch (e: CancellationException) {
        closedHere = true
        // Closed before the failure arrives, so a later receive is Closed, not the cancelled call's IOException.
        inbox.close()
        webSocket.cancel()
        throw e
    }

    override fun close() {
        closedHere = true
        webSocket.close(NORMAL_CLOSURE, null)
        inbox.close()
    }

    override fun toString(): String = "OkHttpRelaySocket(<redacted>)"

    private inner class Listener : WebSocketListener() {
        override fun onMessage(webSocket: WebSocket, text: String) {
            inbox.trySend(RelaySocketMessage.Text(text))
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            inbox.trySend(RelaySocketMessage.Binary(bytes.toByteArray()))
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(NORMAL_CLOSURE, null)
            inbox.close()
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            inbox.close()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            inbox.close(t as? IOException ?: IOException("relay socket failed", t))
        }
    }

    private companion object {
        const val NORMAL_CLOSURE = 1000
    }
}
