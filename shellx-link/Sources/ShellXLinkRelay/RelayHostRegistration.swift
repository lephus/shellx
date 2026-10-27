import Foundation

/// What a host registration reports about itself. Codes only: never a ticket or a key.
public enum RelayHostEvent: Equatable, Sendable {
    /// The slot is registered (the first time, or again after the old registration died).
    case registered
    /// A new registration took over from the old one without a gap.
    case renewed
    /// An attempt or the live registration failed; `code` is the server code, or `closed`,
    /// `timeout`, `url`.
    case failed(code: String)
    /// Too many failures in a row: `run` throws next.
    case gaveUp(code: String)
}

/// Keeps a host registered on a relay slot and hands every incoming circuit to a callback.
///
/// Each registration attempt fetches a fresh ticket from the provider. The relay ends a
/// registration when its ticket expires, so a new registration is opened before that and takes
/// over (make-before-break: a second `register` on a slot replaces the first, and circuits are
/// separate sockets). A dropped socket is registered again with backoff, until the calling task
/// is cancelled or `maxConsecutiveFailures` failures happen in a row.
public actor RelayHostRegistration {
    private let relayURL: URL
    private let slot: String
    private let tickets: TicketProvider
    private let renewLead: Duration
    private let maxConsecutiveFailures: Int
    private let onEvent: @Sendable (RelayHostEvent) -> Void
    private var control: RelaySocket?
    private var running = false

    /// - Parameters:
    ///   - renewLead: How long before its ticket ends a registration is replaced (never later than
    ///     half the ticket's lifetime). The new socket registers before the old one closes.
    ///   - maxConsecutiveFailures: After the first registration, this many failures in a row end
    ///     `run` with the last error.
    ///   - onEvent: Called synchronously, in order, with codes only (never tickets).
    public init(
        relayURL: URL,
        slot: String,
        renewLead: Duration = .seconds(20),
        maxConsecutiveFailures: Int = 5,
        onEvent: @escaping @Sendable (RelayHostEvent) -> Void = { _ in },
        tickets: @escaping TicketProvider
    ) {
        self.relayURL = relayURL
        self.slot = slot
        self.renewLead = renewLead
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.onEvent = onEvent
        self.tickets = tickets
    }

    /// Registers the slot and serves incoming circuits until cancelled.
    ///
    /// `onCircuit` owns the circuit it receives; the circuit is closed when the callback
    /// returns. Circuits keep running across re-registrations and are cancelled with `run`.
    ///
    /// Throws when the first registration fails for a reason a retry cannot fix (a refused
    /// ticket, a ticket provider error, a protocol violation). After one registration has
    /// succeeded, every failure is retried and reported through `onEvent`, until
    /// `maxConsecutiveFailures` in a row end `run` with the last error.
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

    private struct Opened: Sendable {
        var socket: RelaySocket
        /// When to open the next registration: counted on the continuous clock from the moment the ticket
        /// arrived, so the Mac's wall clock never moves it.
        var renewAt: ContinuousClock.Instant
        var leaseSeconds: UInt32
    }

    private struct Live {
        var id: Int
        var socket: RelaySocket
    }

    /// What the supervisor loop in `serve` reacts to. Every task it starts reports through one
    /// stream, so all registration state changes on a single task.
    private enum Signal: Sendable {
        case opened(Result<Opened, any Error>)
        case incoming(Incoming)
        case ended(id: Int, error: any Error)
        case renewDue(id: Int)
        case retry
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

    private nonisolated func serve(
        onCircuit: @escaping @Sendable (any RelayCircuit) async -> Void
    ) async throws {
        let endpoint = try RelayEndpoint.control(relayURL)
        let slot = self.slot
        let tickets = self.tickets
        let renewLead = self.renewLead
        let maxFailures = max(1, maxConsecutiveFailures)
        let onEvent = self.onEvent
        let (signals, emit) = AsyncStream.makeStream(of: Signal.self)

        try await withThrowingDiscardingTaskGroup { group in
            var current: Live?
            var nextID = 0
            var opening = false
            // The live registration ended while a replacement was opening: that is the relay
            // swapping them (it closes the old socket before it answers the new one), not a failure.
            var supersededWhileOpening = false
            var retryScheduled = false
            var everRegistered = false
            var failures = 0
            var backoff = Duration.milliseconds(100)
            defer { current?.socket.close() }

            func open() {
                opening = true
                group.addTask {
                    let result: Result<Opened, any Error>
                    do {
                        result = .success(try await Self.open(
                            endpoint: endpoint, slot: slot, tickets: tickets, renewLead: renewLead))
                    } catch {
                        result = .failure(error)
                    }
                    if Task.isCancelled, case .success(let opened) = result { opened.socket.close() }
                    emit.yield(.opened(result))
                }
            }

            func scheduleRetry() {
                guard !retryScheduled else { return }
                retryScheduled = true
                let delay = backoff
                backoff = min(backoff * 2, .seconds(5))
                group.addTask {
                    try? await Task.sleep(for: delay)
                    emit.yield(.retry)
                }
            }

            // Counts one failure while no registration is live (after the first one), reports it,
            // and gives up when too many in a row have happened.
            func failed(_ error: any Error) throws {
                failures += 1
                let code = Self.code(for: error)
                if failures >= maxFailures {
                    onEvent(.gaveUp(code: code))
                    throw error
                }
                onEvent(.failed(code: code))
                scheduleRetry()
            }

            open()
            for await signal in signals {
                try Task.checkCancellation()
                switch signal {
                case .opened(.success(let opened)):
                    opening = false
                    everRegistered = true
                    failures = 0
                    backoff = .milliseconds(100)
                    nextID += 1
                    let id = nextID
                    let replaced = current != nil || supersededWhileOpening
                    supersededWhileOpening = false
                    let previous = current
                    current = Live(id: id, socket: opened.socket)
                    await attach(opened.socket)
                    onEvent(replaced ? .renewed : .registered)
                    // The relay closes the replaced socket itself; its pump drains what was queued
                    // before the swap. Close it only if the relay has not within a few seconds.
                    if let stale = previous?.socket {
                        group.addTask {
                            try? await Task.sleep(for: .seconds(5))
                            stale.close()
                        }
                    }
                    group.addTask {
                        do {
                            try await Self.pump(opened.socket, leaseSeconds: opened.leaseSeconds) {
                                emit.yield(.incoming($0))
                            }
                        } catch {
                            opened.socket.close()
                            emit.yield(.ended(id: id, error: error))
                        }
                    }
                    group.addTask {
                        try? await Task.sleep(until: opened.renewAt, clock: .continuous)
                        emit.yield(.renewDue(id: id))
                    }
                case .opened(.failure(let error)):
                    opening = false
                    supersededWhileOpening = false
                    if Task.isCancelled { throw CancellationError() }
                    if !everRegistered {
                        // Before the first registration only carrier problems are retried, silently.
                        if !Self.isRetryable(error) { throw error }
                        scheduleRetry()
                    } else if current != nil {
                        // A failed renewal never ends a live registration: report it, keep the
                        // old socket, and try again until that one ends.
                        onEvent(.failed(code: Self.code(for: error)))
                        scheduleRetry()
                    } else {
                        try failed(error)
                    }
                case .incoming(let incoming):
                    group.addTask {
                        await Self.accept(incoming, endpoint: endpoint, slot: slot, onCircuit: onCircuit)
                    }
                case let .ended(id, error):
                    guard current?.id == id else { continue }
                    current = nil
                    if Task.isCancelled { throw CancellationError() }
                    if opening {
                        supersededWhileOpening = true
                        continue
                    }
                    try failed(error)
                case .renewDue(let id):
                    if current?.id == id, !opening { open() }
                case .retry:
                    retryScheduled = false
                    if !opening { open() }
                }
            }
            throw CancellationError()
        }
    }

    /// When to open the next registration, counted from the moment the ticket arrived: half the ticket's
    /// lifetime at the latest, `renewLead` before it ends at the earliest, and never sooner than 1 s.
    ///
    /// The lifetime is the server's own `expires_at - issued_at`: both come from the server's clock, so a Mac
    /// clock that runs ahead (which used to collapse the delay to 1 s, a ticket mint and register about once a
    /// second) or behind (which used to outlive the ticket, losing make-before-break) changes nothing. Only a
    /// ticket without `issued_at` compares its expiry with `now`, this device's clock at arrival.
    static func renewDelay(issuedAtUnix: Int64?, expiresAtUnix: Int64, renewLead: Duration, now: Date) -> Duration {
        let remaining: Double = if let issuedAtUnix {
            Double(expiresAtUnix) - Double(issuedAtUnix)
        } else {
            Double(expiresAtUnix) - now.timeIntervalSince1970
        }
        let lifetime = max(0, remaining)
        let lead = Double(renewLead.components.seconds) + Double(renewLead.components.attoseconds) / 1e18
        return .seconds(max(1, max(lifetime / 2, lifetime - lead)))
    }

    /// A secret-free code for a failure: the relay's code, or `closed`, `timeout`, `url`.
    private static func code(for error: any Error) -> String {
        switch error {
        case RelayError.server(let code, _): return code
        case RelayError.closed: return "closed"
        case RelayError.protocolViolation, RelayError.insecureTransport: return "url"
        case let urlError as URLError: return urlError.code == .timedOut ? "timeout" : "closed"
        default:
            // A socket the relay (or this side) closed can surface as a POSIX "not connected".
            return (error as NSError).domain == NSPOSIXErrorDomain ? "closed" : "error"
        }
    }

    /// Opens a control socket with a fresh ticket and registers the slot on it.
    private static func open(
        endpoint: URL,
        slot: String,
        tickets: TicketProvider,
        renewLead: Duration
    ) async throws -> Opened {
        let ticket = try await tickets()
        let arrived = ContinuousClock.now
        let claims = ticket.claims
        let renewAt = arrived + renewDelay(
            issuedAtUnix: claims?.issuedAtUnix, expiresAtUnix: claims?.expiresAtUnix ?? ticket.expiresAtUnix,
            renewLead: renewLead, now: Date())
        let socket = RelaySocket(url: endpoint, bearer: ticket.ticket)
        do {
            try await socket.send(.register(
                protocol: RelayProtocol.version, slot: slot, ticket: ticket.ticket))
            let reply = try await withRelayTimeout(RelayProtocol.controlTimeout) {
                try await socket.receiveControl()
            }
            switch reply {
            case .registered(let lease):
                return Opened(socket: socket, renewAt: renewAt, leaseSeconds: lease)
            case let .error(code, _, retryable):
                throw RelayError.server(code: code, retryable: retryable)
            default:
                throw RelayError.protocolViolation("relay did not answer register with registered")
            }
        } catch {
            socket.close()
            throw error
        }
    }

    /// One registered control socket's life: heartbeat and dispatch until it fails.
    /// Never returns normally.
    private static func pump(
        _ socket: RelaySocket,
        leaseSeconds: UInt32,
        onIncoming: @Sendable (Incoming) -> Void
    ) async throws {
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
        case RelayError.protocolViolation, RelayError.insecureTransport:
            return false
        case is URLError:
            return true
        default:
            return (error as NSError).domain == NSURLErrorDomain
        }
    }
}
