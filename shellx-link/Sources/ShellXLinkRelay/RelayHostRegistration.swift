import Foundation

/// Keeps a host registered on a relay slot and hands every incoming circuit to a callback.
///
/// Each registration attempt fetches a fresh ticket from the provider. The relay ends a
/// registration when its ticket expires or the socket drops; `run` then registers again with
/// backoff, until the calling task is cancelled.
public actor RelayHostRegistration {
    private let relayURL: URL
    private let slot: String
    private let tickets: TicketProvider
    private var control: RelaySocket?
    private var running = false

    public init(relayURL: URL, slot: String, tickets: @escaping TicketProvider) {
        self.relayURL = relayURL
        self.slot = slot
        self.tickets = tickets
    }

    /// Registers the slot and serves incoming circuits until cancelled.
    ///
    /// `onCircuit` owns the circuit it receives; the circuit is closed when the callback
    /// returns. Circuits keep running across re-registrations and are cancelled with `run`.
    ///
    /// Throws when the first registration fails for a reason a retry cannot fix (a refused
    /// ticket, a ticket provider error, a protocol violation). After one registration has
    /// succeeded, every failure is retried.
    public nonisolated func run(
        onCircuit: @escaping @Sendable (any RelayCircuit) async -> Void
    ) async throws {
        try await begin()
        do {
            try await serve(onCircuit: onCircuit)
        } catch {
            await end()
            throw error
        }
    }

    /// Testing hook: closes the current control socket as if the network dropped it.
    public func _dropControlForTesting() {
        control?.close()
    }

    // MARK: - Registration loop

    private struct Incoming: Sendable {
        var circuit: String
        var lane: String
        var generation: UInt64
        var joinTicket: String
    }

    private func begin() throws {
        guard !running else {
            throw RelayError.protocolViolation("this registration is already running")
        }
        running = true
    }

    private func end() {
        running = false
        control = nil
    }

    private func attach(_ socket: RelaySocket) {
        control = socket
    }

    private func detach(_ socket: RelaySocket) {
        if control === socket { control = nil }
    }

    private nonisolated func serve(
        onCircuit: @escaping @Sendable (any RelayCircuit) async -> Void
    ) async throws {
        let endpoint = try RelayEndpoint.control(relayURL)
        let slot = self.slot
        try await withThrowingDiscardingTaskGroup { circuits in
            var registered = false
            var backoff = Duration.milliseconds(100)
            while true {
                try Task.checkCancellation()
                do {
                    try await registerOnce(
                        endpoint: endpoint,
                        onRegistered: {
                            registered = true
                            backoff = .milliseconds(100)
                        },
                        onIncoming: { incoming in
                            circuits.addTask {
                                await Self.accept(
                                    incoming, endpoint: endpoint, slot: slot, onCircuit: onCircuit)
                            }
                        })
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    if !registered && !Self.isRetryable(error) { throw error }
                }
                try await Task.sleep(for: backoff)
                backoff = min(backoff * 2, .seconds(5))
            }
        }
    }

    /// One control socket's life: register, then heartbeat and dispatch until it fails.
    /// Never returns normally.
    private nonisolated func registerOnce(
        endpoint: URL,
        onRegistered: () -> Void,
        onIncoming: (Incoming) -> Void
    ) async throws {
        let ticket = try await tickets()
        let socket = RelaySocket(url: endpoint, bearer: ticket.ticket)
        await attach(socket)
        do {
            try await socket.send(.register(
                protocol: RelayProtocol.version, slot: slot, ticket: ticket.ticket))
            let reply = try await withRelayTimeout(RelayProtocol.controlTimeout) {
                try await socket.receiveControl()
            }
            let leaseSeconds: UInt32
            switch reply {
            case .registered(let lease):
                leaseSeconds = lease
            case let .error(code, _, retryable):
                throw RelayError.server(code: code, retryable: retryable)
            default:
                throw RelayError.protocolViolation("relay did not answer register with registered")
            }
            onRegistered()
            // Ping three times per lease so the relay keeps the registration alive.
            let heartbeat = Duration.seconds(Int(max(leaseSeconds, 3) / 3))
            try await withThrowingTaskGroup(of: Void.self) { pings in
                pings.addTask {
                    var nonce: UInt64 = 0
                    while true {
                        try await Task.sleep(for: heartbeat)
                        nonce &+= 1
                        try await socket.send(.ping(nonce: nonce))
                    }
                }
                while true {
                    switch try await socket.receiveControl() {
                    case let .incoming(circuit, lane, generation, joinTicket):
                        onIncoming(Incoming(
                            circuit: circuit, lane: lane, generation: generation,
                            joinTicket: joinTicket))
                    case .ping(let nonce):
                        try await socket.send(.pong(nonce: nonce))
                    case let .error(code, _, retryable):
                        throw RelayError.server(code: code, retryable: retryable)
                    default:
                        continue
                    }
                }
            }
        } catch {
            socket.close()
            await detach(socket)
            throw error
        }
    }

    private static func accept(
        _ incoming: Incoming,
        endpoint: URL,
        slot: String,
        onCircuit: @Sendable (any RelayCircuit) async -> Void
    ) async {
        guard let circuit = try? await RelayCircuitJoin.join(
            endpoint: endpoint, slot: slot, role: .daemon, circuit: incoming.circuit,
            lane: incoming.lane, generation: incoming.generation, ticket: incoming.joinTicket)
        else {
            return
        }
        await onCircuit(circuit)
        await circuit.close()
    }

    /// Whether a failed first registration is worth retrying (a carrier problem) rather than
    /// reported (a refusal a fresh attempt will not change).
    private static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case let RelayError.server(code, retryable):
            return retryable && !RelayProtocol.authenticationCodes.contains(code)
        case RelayError.closed:
            return true
        case RelayError.protocolViolation:
            return false
        case is URLError:
            return true
        default:
            return (error as NSError).domain == NSURLErrorDomain
        }
    }
}
