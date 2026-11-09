package com.shellx.link.account

import com.shellx.link.core.RelayException
import com.shellx.link.core.RelaySocket
import com.shellx.link.core.RelaySocketFactory
import com.shellx.link.core.RelaySocketMessage
import com.shellx.link.core.RelayTransportPolicy
import java.io.IOException
import java.net.URI
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
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
 * One OkHttp WebSocket. Incoming binary messages queue up to [MAX_QUEUED_BYTES] (plan 3G Task 4b): past that, OkHttp's
 * reader thread waits in [InboxBudget.take] until [receive] takes one, so TCP holds back the rest and the Mac's host
 * sends a slow phone fewer, larger deltas (PROTOCOL.md 11.4), as the iPhone's `URLSessionWebSocketTask`, which reads
 * only when asked, does. Nothing is ever dropped: binary messages are Noise ciphertext, and a lost one would break the
 * cipher stream. Text messages (relay control: pings, errors) never wait and are not counted; they are few and small.
 * The session's reader drains the inbox at decrypting speed (its terminal frames never wait: `TerminalPushQueue` drops
 * what its consumer cannot take), so the bound engages only when that reader falls behind, and a reply or ping waits
 * at most for the bytes queued ahead of it.
 */
internal class OkHttpRelaySocket(client: OkHttpClient, request: Request) : RelaySocket {
    companion object {
        /** 1 MiB: 16 frames of the largest size (a Noise message is at most 65 535 bytes). */
        const val MAX_QUEUED_BYTES = 1_048_576
        private const val NORMAL_CLOSURE = 1000
    }

    private val inbox = Channel<RelaySocketMessage>(Channel.UNLIMITED)
    private val budget = InboxBudget(MAX_QUEUED_BYTES)
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

    /** The bytes of the binary messages queued. For tests. */
    internal val queuedBytes: Int get() = budget.queued

    override suspend fun receive(): RelaySocketMessage = try {
        inbox.receive().also { if (it is RelaySocketMessage.Binary) budget.give(it.bytes.size) }
    } catch (_: ClosedReceiveChannelException) {
        throw RelayException.Closed()
    } catch (e: CancellationException) {
        closedHere = true
        // Closed before the failure arrives, so a later receive is Closed, not the cancelled call's IOException.
        inbox.close()
        budget.close()
        webSocket.cancel()
        throw e
    }

    override fun close() {
        closedHere = true
        webSocket.close(NORMAL_CLOSURE, null)
        inbox.close()
        // Frees a reader thread that waits for room, so OkHttp can finish the close.
        budget.close()
    }

    override fun toString(): String = "OkHttpRelaySocket(<redacted>)"

    private inner class Listener : WebSocketListener() {
        override fun onMessage(webSocket: WebSocket, text: String) {
            inbox.trySend(RelaySocketMessage.Text(text))
        }

        /** On OkHttp's reader thread: waits here while the inbox is full. */
        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            when (budget.take(bytes.size)) {
                InboxBudget.Taken.YES -> if (inbox.trySend(RelaySocketMessage.Binary(bytes.toByteArray())).isFailure) {
                    budget.give(bytes.size)
                }
                InboxBudget.Taken.CLOSED -> Unit
                // A message dropped here would break the cipher stream: the socket fails instead.
                InboxBudget.Taken.INTERRUPTED -> {
                    inbox.close(IOException("relay socket reader was interrupted"))
                    webSocket.cancel()
                }
            }
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(NORMAL_CLOSURE, null)
            inbox.close()
            budget.close()
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            inbox.close()
            budget.close()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            inbox.close(t as? IOException ?: IOException("relay socket failed", t))
            budget.close()
        }
    }
}

/**
 * The bytes a socket's inbox may hold. [take] blocks its thread (OkHttp's reader) until the bytes fit, or the inbox
 * is empty: a message larger than the limit still goes in alone, so nothing waits forever.
 */
internal class InboxBudget(private val limit: Int) {
    enum class Taken { YES, CLOSED, INTERRUPTED }

    private val lock = ReentrantLock()
    private val room = lock.newCondition()
    private var held = 0
    private var open = true

    val queued: Int get() = lock.withLock { held }

    fun take(bytes: Int): Taken = lock.withLock {
        try {
            while (open && held > 0 && held + bytes > limit) room.await()
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            return Taken.INTERRUPTED
        }
        if (!open) return Taken.CLOSED
        held += bytes
        Taken.YES
    }

    fun give(bytes: Int) = lock.withLock {
        held -= bytes
        room.signalAll()
    }

    /** Wakes every waiting thread; every later [take] is [Taken.CLOSED]. Idempotent. */
    fun close() = lock.withLock {
        open = false
        room.signalAll()
    }
}
