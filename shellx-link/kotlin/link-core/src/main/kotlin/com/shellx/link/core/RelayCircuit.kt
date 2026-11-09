package com.shellx.link.core

import java.net.URI
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration
import kotlinx.coroutines.withTimeoutOrNull

/** An ordered binary pipe: one send arrives as one receive. Receive from one coroutine at a time. */
interface RelayCircuit {
    /** [RelayException.Closed] once the circuit has ended. */
    suspend fun send(data: ByteArray)

    /** The next frame. [RelayException.Closed] once the circuit has ended; cancelling a pending receive closes the circuit. */
    suspend fun receive(): ByteArray

    /** Ends the circuit for both sides. Idempotent. */
    fun close()
}

/** A ready circuit socket: binary messages are frames, text messages are relay control. */
internal class WebSocketRelayCircuit(private val socket: RelaySocket) : RelayCircuit {
    override suspend fun send(data: ByteArray) {
        try {
            socket.sendBinary(data)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            throw RelayException.Closed()
        }
    }

    override suspend fun receive(): ByteArray {
        while (true) {
            when (val message = receiveFromSocket()) {
                is RelaySocketMessage.Binary -> return message.bytes
                is RelaySocketMessage.Text -> handleControl(message.text)
            }
        }
    }

    override fun close() = socket.close()

    private suspend fun receiveFromSocket(): RelaySocketMessage = try {
        socket.receive()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        throw RelayException.Closed()
    }

    /** Answers a relay ping, skips a pong, and throws for anything else. */
    private suspend fun handleControl(text: String) {
        val control = try {
            RelayControl.decode(text)
        } catch (_: RelayException) {
            null
        }
        when (control) {
            is RelayControl.Ping -> try {
                socket.sendText(RelayControl.Pong(control.nonce).encodeText())
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                throw RelayException.Closed()
            }
            is RelayControl.Pong -> Unit
            is RelayControl.Error -> {
                socket.close()
                // The relay reports the other side leaving as an error; for this side it is the normal end.
                if (control.code == "peer-disconnected") throw RelayException.Closed()
                throw RelayException.Server(control.code, control.retryable)
            }
            else -> {
                socket.close()
                throw RelayException.ProtocolViolation("relay sent unexpected circuit control")
            }
        }
    }
}

/** Joins one side of an allocated circuit on its own WebSocket and waits for `ready`. */
object RelayCircuitJoin {
    suspend fun join(
        sockets: RelaySocketFactory,
        endpoint: URI,
        slot: String,
        role: RelayRole,
        circuit: String,
        lane: String,
        generation: ULong,
        ticket: String,
        controlTimeout: Duration = RelayProtocol.CONTROL_TIMEOUT,
    ): RelayCircuit {
        val socket = sockets.open(RelayEndpoint.circuit(endpoint, circuit), bearer = ticket)
        try {
            socket.sendText(RelayControl.Join(RelayProtocol.VERSION, slot, circuit, lane, generation, ticket, role).encodeText())
            socket.awaitControl(controlTimeout) { c ->
                c is RelayControl.Ready && c.circuit == circuit && c.lane == lane && c.generation == generation
            }
        } catch (e: Throwable) {
            socket.close()
            throw e
        }
        return WebSocketRelayCircuit(socket)
    }
}

/**
 * Reads control messages until [accept] takes one, within [timeout]: `error` is [RelayException.Server], `ping` is
 * answered, anything else is skipped, and binary data is a [RelayException.ProtocolViolation]. No answer in time is
 * [RelayException.TimedOut].
 */
internal suspend fun RelaySocket.awaitControl(timeout: Duration, accept: (RelayControl) -> Boolean): RelayControl =
    withTimeoutOrNull(timeout) {
        var accepted: RelayControl? = null
        while (accepted == null) {
            val control = when (val message = receive()) {
                is RelaySocketMessage.Text -> RelayControl.decode(message.text)
                is RelaySocketMessage.Binary ->
                    throw RelayException.ProtocolViolation("relay sent binary data before the circuit was ready")
            }
            when {
                accept(control) -> accepted = control
                control is RelayControl.Error -> throw RelayException.Server(control.code, control.retryable)
                control is RelayControl.Ping -> sendText(RelayControl.Pong(control.nonce).encodeText())
            }
        }
        accepted
    } ?: throw RelayException.TimedOut()
