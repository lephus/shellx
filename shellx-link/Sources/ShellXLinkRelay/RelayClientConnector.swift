import Foundation

/// Opens client circuits to a host registered on the relay.
public enum RelayClientConnector {
    /// Asks the relay for a circuit to `slot` with a connect ticket, then joins it on a
    /// separate WebSocket and returns once the relay reports both sides ready.
    ///
    /// Throws `RelayError.server` when the relay refuses (for example `invalid-ticket`, or a
    /// retryable `slot-offline` while no host is registered).
    public static func connect(
        relayURL: URL,
        slot: String,
        ticket: RelayTicket
    ) async throws -> any RelayCircuit {
        let endpoint = try RelayEndpoint.control(relayURL)
        let lane = RelayLane.random()
        let generation: UInt64 = 0
        let control = RelaySocket(url: endpoint, bearer: ticket.ticket)
        let joinTicket: (circuit: String, ticket: String)
        do {
            try await control.send(.connect(
                protocol: RelayProtocol.version, slot: slot, ticket: ticket.ticket, lane: lane,
                generation: generation))
            joinTicket = try await withRelayTimeout(RelayProtocol.controlTimeout) {
                while true {
                    switch try await control.receiveControl() {
                    case let .allocated(circuit, allocatedLane, allocatedGeneration, joinTicket)
                        where allocatedLane == lane && allocatedGeneration == generation:
                        return (circuit, joinTicket)
                    case let .error(code, _, retryable):
                        throw RelayError.server(code: code, retryable: retryable)
                    case .ping(let nonce):
                        try await control.send(.pong(nonce: nonce))
                    default:
                        continue
                    }
                }
            }
        } catch {
            control.close()
            throw error
        }
        // The allocation outlives the client control socket, which this client does not reuse.
        control.close()
        return try await RelayCircuitJoin.join(
            endpoint: endpoint, slot: slot, role: .client, circuit: joinTicket.circuit, lane: lane,
            generation: generation, ticket: joinTicket.ticket)
    }
}
