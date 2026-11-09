package com.shellx.link.core

import java.io.IOException
import java.net.URI
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.channels.Channel

/**
 * A [RelaySocketFactory] whose sockets answer from a script: each text the client sends is passed to
 * `respond(index of the socket, text)`, and the frames it returns are queued for that socket's `receive()`.
 */
class ScriptedRelaySockets(
    private val respond: (index: Int, sentControl: String) -> List<RelaySocketMessage> = { _, _ -> emptyList() },
) : RelaySocketFactory {
    val opened: MutableList<Opened> = CopyOnWriteArrayList()

    override fun open(url: URI, bearer: String?): RelaySocket {
        val index = opened.size
        return Opened(url, bearer) { respond(index, it) }.also { opened += it }
    }

    /** Injects [message] into socket [index]. */
    fun push(index: Int, message: RelaySocketMessage) = opened[index].push(message)
}

/** One scripted socket: what was opened, what the client sent, and whether it closed it. */
class Opened(
    val url: URI,
    val bearer: String?,
    private val respond: (String) -> List<RelaySocketMessage> = { emptyList() },
) : RelaySocket {
    /** Every text the client sent, in order. */
    val sent: MutableList<String> = CopyOnWriteArrayList()

    /** Every binary message the client sent, in order. */
    val sentBinary: MutableList<ByteArray> = CopyOnWriteArrayList()

    @Volatile var closed: Boolean = false
        private set

    /** When set, sends throw it. */
    @Volatile var failSends: Exception? = null

    private val inbox = Channel<RelaySocketMessage>(Channel.UNLIMITED)

    /** The control messages the client sent, decoded. */
    val sentControl: List<RelayControl> get() = sent.map { RelayControl.decode(it) }

    override suspend fun sendText(text: String) {
        if (closed) throw RelayException.Closed()
        failSends?.let { throw it }
        sent += text
        respond(text).forEach { inbox.trySend(it) }
    }

    override suspend fun sendBinary(bytes: ByteArray) {
        if (closed) throw RelayException.Closed()
        failSends?.let { throw it }
        sentBinary += bytes.copyOf()
    }

    override suspend fun receive(): RelaySocketMessage {
        if (closed) throw RelayException.Closed()
        val result = try {
            inbox.receiveCatching()
        } catch (e: CancellationException) {
            // The RelaySocket rule: cancelling a pending receive closes the socket.
            close()
            throw e
        }
        result.getOrNull()?.let { return it }
        throw result.exceptionOrNull() ?: RelayException.Closed()
    }

    override fun close() {
        closed = true
        inbox.close()
    }

    fun push(message: RelaySocketMessage) {
        inbox.trySend(message)
    }

    /** Ends the socket as a transport failure: the next `receive()` throws [error]. */
    fun fail(error: IOException) {
        inbox.close(error)
    }
}

fun text(control: RelayControl): RelaySocketMessage = RelaySocketMessage.Text(control.encodeText())
