package com.shellx.link.account

import com.shellx.link.core.RelayCircuit
import com.shellx.link.core.RelayCircuitJoin
import com.shellx.link.core.RelayControl
import com.shellx.link.core.RelayEndpoint
import com.shellx.link.core.RelayException
import com.shellx.link.core.RelayProtocol
import com.shellx.link.core.RelayRole
import com.shellx.link.core.RelaySocket
import com.shellx.link.core.RelaySocketFactory
import com.shellx.link.core.RelaySocketMessage
import java.net.URI
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * A test host on a real relay: registers [slot] as `RelayHostRegistration.swift`'s `open` does, then joins each
 * incoming circuit as the daemon and hands it to `onCircuit` in its own coroutine, answering relay pings meanwhile.
 *
 * One registration and no renewal, so a test must finish within the register ticket's 120 s lifetime. The relay keeps
 * a daemon's lease (30 s by default) only while the daemon writes to its control socket, so the host pings every
 * lease / 3, as Swift's `pump` does.
 */
class TestRelayHost(
    private val sockets: RelaySocketFactory,
    private val relayUrl: URI,
    private val slot: String,
    private val minter: TestTicketMinter,
) {
    fun start(scope: CoroutineScope, onCircuit: suspend (RelayCircuit) -> Unit): Job = scope.launch {
        val endpoint = RelayEndpoint.control(relayUrl)
        val ticket = minter.mint("register", slot)
        val control = sockets.open(endpoint, bearer = ticket.ticket)
        try {
            control.sendText(RelayControl.Register(RelayProtocol.VERSION, slot, ticket.ticket).encodeText())
            val registered = withTimeoutOrNull(RelayProtocol.CONTROL_TIMEOUT) {
                var accepted: RelayControl.Registered? = null
                while (accepted == null) {
                    when (val reply = control.receiveControl()) {
                        is RelayControl.Registered -> accepted = reply
                        is RelayControl.Error -> throw RelayException.Server(reply.code, reply.retryable)
                        is RelayControl.Ping -> control.sendText(RelayControl.Pong(reply.nonce).encodeText())
                        else -> throw RelayException.ProtocolViolation("relay did not answer register with registered")
                    }
                }
                accepted
            } ?: throw RelayException.TimedOut()
            // Heartbeat: a failed send ends this job, and with it the registration.
            val heartbeat = (maxOf(registered.leaseSeconds, 3L) / 3).seconds
            launch {
                var nonce = 0uL
                while (true) {
                    delay(heartbeat)
                    nonce += 1u
                    control.sendText(RelayControl.Ping(nonce).encodeText())
                }
            }
            while (true) {
                when (val message = control.receiveControl()) {
                    is RelayControl.Incoming -> launch { accept(endpoint, message, onCircuit) }
                    is RelayControl.Ping -> control.sendText(RelayControl.Pong(message.nonce).encodeText())
                    is RelayControl.Error -> throw RelayException.Server(message.code, message.retryable)
                    else -> Unit
                }
            }
        } finally {
            control.close()
        }
    }

    private suspend fun accept(endpoint: URI, incoming: RelayControl.Incoming, onCircuit: suspend (RelayCircuit) -> Unit) {
        val circuit = try {
            RelayCircuitJoin.join(
                sockets, endpoint, slot, RelayRole.DAEMON, incoming.circuit, incoming.lane, incoming.generation,
                incoming.joinTicket,
            )
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return
        }
        try {
            onCircuit(circuit)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // One circuit ending badly (the client left mid-read) must not end the registration.
        } finally {
            circuit.close()
        }
    }

    /** The next control message; binary data on the control socket is a protocol violation. */
    private suspend fun RelaySocket.receiveControl(): RelayControl = when (val message = receive()) {
        is RelaySocketMessage.Text -> RelayControl.decode(message.text)
        is RelaySocketMessage.Binary -> throw RelayException.ProtocolViolation("relay sent binary data on the control socket")
    }
}
