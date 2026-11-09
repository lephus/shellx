package com.shellx.link.core

import java.net.URI
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay

/** Opens client circuits to a host registered on the relay. */
object RelayClientConnector {
    val DEFAULT_SLOT_OFFLINE_RETRIES: List<Duration> = listOf(500.milliseconds, 1.seconds, 2.seconds)

    /**
     * Asks the relay for a circuit to [slot] with a connect ticket, then joins it on a separate WebSocket and returns
     * once the relay reports it ready.
     *
     * A retryable `slot-offline` (the host is between registrations) is retried after each delay in
     * [slotOfflineRetries], with the same ticket: a ticket is reusable until it expires. Throws
     * [RelayException.Server] when the relay refuses (`invalid-ticket`, or `slot-offline` once the retries are used
     * up), [RelayException.TimedOut] when a control exchange gets no answer within [controlTimeout], and the socket's
     * `IOException` unchanged.
     */
    suspend fun connect(
        relayUrl: URI,
        slot: String,
        ticket: RelayTicket,
        sockets: RelaySocketFactory,
        slotOfflineRetries: List<Duration> = DEFAULT_SLOT_OFFLINE_RETRIES,
        controlTimeout: Duration = RelayProtocol.CONTROL_TIMEOUT,
    ): RelayCircuit {
        val delays = slotOfflineRetries.iterator()
        while (true) {
            try {
                return connectOnce(relayUrl, slot, ticket, sockets, controlTimeout)
            } catch (e: RelayException.Server) {
                if (e.code != "slot-offline" || !e.retryable || !delays.hasNext()) throw e
                delay(delays.next())
            }
        }
    }

    private suspend fun connectOnce(
        relayUrl: URI,
        slot: String,
        ticket: RelayTicket,
        sockets: RelaySocketFactory,
        controlTimeout: Duration,
    ): RelayCircuit {
        val endpoint = RelayEndpoint.control(relayUrl)
        val lane = RelayLane.random()
        val generation = 0uL
        val control = sockets.open(endpoint, bearer = ticket.ticket)
        val allocated = try {
            control.sendText(RelayControl.Connect(RelayProtocol.VERSION, slot, ticket.ticket, lane, generation).encodeText())
            control.awaitControl(controlTimeout) { c ->
                c is RelayControl.Allocated && c.lane == lane && c.generation == generation
            } as RelayControl.Allocated
        } finally {
            // The allocation outlives the client control socket, which this client does not reuse.
            control.close()
        }
        return RelayCircuitJoin.join(
            sockets, endpoint, slot, RelayRole.CLIENT, allocated.circuit, lane, generation, allocated.joinTicket,
            controlTimeout,
        )
    }
}
