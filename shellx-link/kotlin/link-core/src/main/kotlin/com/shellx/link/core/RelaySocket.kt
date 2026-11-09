package com.shellx.link.core

import java.net.URI

/** One WebSocket message. A text message is relay control and may carry a ticket, so neither kind prints its content. */
sealed interface RelaySocketMessage {
    data class Text(val text: String) : RelaySocketMessage {
        override fun toString(): String = "Text(<${text.length} chars>)"
    }

    class Binary(val bytes: ByteArray) : RelaySocketMessage {
        override fun equals(other: Any?): Boolean = other is Binary && bytes.contentEquals(other.bytes)

        override fun hashCode(): Int = bytes.contentHashCode()

        override fun toString(): String = "Binary(<${bytes.size} bytes>)"
    }
}

/** One WebSocket to the relay. Cancelling a pending [receive] closes the socket. */
interface RelaySocket {
    /** [RelayException.Closed] when the socket is closed. */
    suspend fun sendText(text: String)

    /** [RelayException.Closed] when the socket is closed. */
    suspend fun sendBinary(bytes: ByteArray)

    /** The next message. [RelayException.Closed] after a close; the transport's `IOException` after a failure. */
    suspend fun receive(): RelaySocketMessage

    /** Idempotent. */
    fun close()
}

/** Opens relay sockets; [bearer] goes in `Authorization: Bearer …` when it is set. */
fun interface RelaySocketFactory {
    fun open(url: URI, bearer: String?): RelaySocket
}
