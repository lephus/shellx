package com.shellx.link.core

import kotlin.coroutines.cancellation.CancellationException
import kotlin.random.Random
import kotlin.random.nextULong
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay

/** Keep-alive timing of a session. Tests shorten it; production uses [STANDARD]. */
data class LinkTimings(
    /** How often an established session sends `ping`. */
    val pingInterval: Duration,
    /** A session that has received nothing for this long is dead, and its circuit is closed. */
    val idleTimeout: Duration,
    /** How long each call waits for its answer. */
    val requestTimeout: Duration = 10.seconds,
) {
    companion object {
        val STANDARD = LinkTimings(pingInterval = 20.seconds, idleTimeout = 45.seconds)
    }
}

/** Where the Link session logs. */
object LinkLog {
    /** Gets event names and protocol error codes only, never content, names, ids, keys, tickets or tokens. */
    @Volatile var sink: (String) -> Unit = {}

    /** Hands [event] to [sink]; a sink that throws loses the event, never the session. */
    internal fun event(event: String) {
        try {
            sink(event)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // A broken log sink must not end a session.
        }
    }
}

/**
 * Wraps a circuit and remembers when a frame last arrived, so a watchdog can close a dead one.
 *
 * A pending `receive()` is never cancelled to enforce a timeout, because that kills a relay circuit. The watchdog
 * closes the circuit instead, and the blocked `receive()` then throws [RelayException.Closed].
 */
internal class WatchedCircuit(private val inner: RelayCircuit) : RelayCircuit {
    @Volatile private var lastReceive = System.nanoTime()

    override suspend fun send(data: ByteArray) = inner.send(data)

    override suspend fun receive(): ByteArray = inner.receive().also { lastReceive = System.nanoTime() }

    override fun close() = inner.close()

    /** Wakes every `idleTimeout / 5` and closes the circuit once nothing has arrived for [idleTimeout]. */
    suspend fun watch(idleTimeout: Duration) {
        val step = idleTimeout / 5
        while (true) {
            if ((System.nanoTime() - lastReceive).nanoseconds >= idleTimeout) {
                LinkLog.event("closing a silent session")
                inner.close()
                return
            }
            delay(step)
        }
    }
}

/** Sends `ping` every [interval], with nonces counting up (wrapping) from [start] + 1, until cancelled or a send fails. */
internal suspend fun runPings(channel: SecureChannel, interval: Duration, start: ULong = Random.nextULong()) {
    var nonce = start
    while (true) {
        delay(interval)
        nonce += 1u
        try {
            channel.send(LinkMessage.Ping(nonce))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return
        }
    }
}
