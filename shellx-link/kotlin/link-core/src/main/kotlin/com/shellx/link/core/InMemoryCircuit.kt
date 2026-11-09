package com.shellx.link.core

import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.channels.Channel

/**
 * The two ends of a connected in-memory circuit, for tests and local probes. It behaves like a relay circuit:
 * - frames arrive in order, one `send` per `receive`;
 * - `close()` on either end ends the circuit for both: pending and later `receive()` and `send()` throw
 *   [RelayException.Closed]. Frames the peer sent before the close are still delivered first, as a relay delivers
 *   them before it reports the disconnect; the closing end drops its own unread frames, as a closed socket does;
 * - cancelling a pending `receive()` closes the circuit, as it closes the relay WebSocket.
 */
fun inMemoryCircuitPair(): Pair<RelayCircuit, RelayCircuit> {
    val pipe = InMemoryPipe()
    return InMemoryCircuit(pipe, 0) to InMemoryCircuit(pipe, 1)
}

private class InMemoryCircuit(private val pipe: InMemoryPipe, private val side: Int) : RelayCircuit {
    override suspend fun send(data: ByteArray) = pipe.send(data, from = side)

    override suspend fun receive(): ByteArray = pipe.receive(side)

    override fun close() = pipe.close(from = side)

    override fun toString(): String = "InMemoryCircuit(side=$side)"
}

/** The shared state of both ends: one inbox per side, and one closed flag. */
private class InMemoryPipe {
    private val closed = AtomicBoolean(false)
    private val inboxes = listOf(Channel<ByteArray>(Channel.UNLIMITED), Channel<ByteArray>(Channel.UNLIMITED))

    fun send(data: ByteArray, from: Int) {
        if (closed.get()) throw RelayException.Closed()
        // A close that lands after the check has closed the inbox, so the frame is refused here.
        if (!inboxes[1 - from].trySend(data.copyOf()).isSuccess) throw RelayException.Closed()
    }

    suspend fun receive(side: Int): ByteArray {
        val result = try {
            inboxes[side].receiveCatching()
        } catch (e: CancellationException) {
            close(from = side)
            throw e
        }
        // A closed inbox still yields what the peer sent before the close, then fails.
        return result.getOrNull() ?: throw RelayException.Closed()
    }

    fun close(from: Int) {
        if (!closed.compareAndSet(false, true)) return
        inboxes.forEach { it.close() }
        // The closing end drops its own unread frames.
        val own = inboxes[from]
        var dropped = own.tryReceive()
        while (dropped.isSuccess) dropped = own.tryReceive()
    }
}
