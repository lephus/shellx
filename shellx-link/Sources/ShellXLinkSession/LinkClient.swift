import Foundation
import ShellXLinkCore
import ShellXLinkRelay

/// Failures of a `LinkClient` session.
public enum LinkClientError: Error, Equatable, Sendable {
    /// The host speaks another protocol version; the user should update the app (PROTOCOL.md 7).
    case protocolMismatch(message: String)
    /// The host answered `hello` with an `error`.
    case rejected(code: String, message: String)
    /// The session ended (closed by either side, or found dead) before an answer arrived.
    case sessionClosed
    /// No answer arrived within the request timeout (10 s by default). The session stays usable.
    case timedOut
}

/// The phone side of ShellX Link: one established session with one host.
public actor LinkClient {
    private typealias Snapshot = (revision: Int, pending: [PendingItem])
    private typealias Change = (revision: Int, added: [PendingItem], resolved: [String])

    /// Every `agent.changed` from the host, in order. Single consumer. It finishes when the
    /// session ends.
    ///
    /// Each change carries the host's `revision`. Compared with the revision of the last change or
    /// snapshot the caller applied: at or below it, the caller already has the change and skips
    /// it; exactly one above, it applies it; further above, it missed one and must resync with
    /// `snapshot()` (PROTOCOL.md section 4).
    public nonisolated let changes: AsyncStream<(revision: Int, added: [PendingItem], resolved: [String])>

    private let changesContinuation: AsyncStream<Change>.Continuation
    private let channel: SecureChannel
    private let pinger: Task<Void, Never>
    private let watchdog: Task<Void, Never>
    private var reader: Task<Void, Never>?
    private var nextWaiterId = 0
    private let requestTimeout: Duration
    private var snapshotWaiters: [Waiter<Snapshot>] = []
    private var replyWaiters: [String: [Waiter<ReplyOutcome>]] = [:]
    /// Per `request_id`, how many `agent.reply.result` frames still belong to replies that timed
    /// out or were cancelled. The host answers every `agent.reply` (PROTOCOL.md 4), so such a
    /// late answer is dropped instead of reaching a newer reply for the same request.
    private var lateReplyResults: [String: Int] = [:]
    private var endError: LinkClientError?

    /// One caller waiting for an answer, and the timer that fails it after `requestTimeout`.
    private struct Waiter<Value: Sendable> {
        let id: Int
        let continuation: CheckedContinuation<Value, any Error>
        let timer: Task<Void, Never>

        func resume(returning value: Value) {
            timer.cancel()
            continuation.resume(returning: value)
        }

        func resume(throwing error: any Error) {
            timer.cancel()
            continuation.resume(throwing: error)
        }
    }

    private init(channel: SecureChannel, watchdog: Task<Void, Never>, timings: LinkTimings) {
        let pingInterval = timings.pingInterval
        requestTimeout = timings.requestTimeout
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self)
        changes = stream
        changesContinuation = continuation
        self.channel = channel
        self.watchdog = watchdog
        pinger = Task { await runPings(on: channel, every: pingInterval) }
    }

    deinit {
        pinger.cancel()
        watchdog.cancel()
        changesContinuation.finish()
        let channel = self.channel
        Task { await channel.close() }
    }

    /// Runs the handshake (initiator, trusting only `hostKey`) and `hello` / `welcome`.
    ///
    /// Throws `NoiseError` when the host is not `hostKey`, `RelayError.closed` when the host drops
    /// the circuit (for example because it does not trust this phone), and `LinkClientError` when
    /// the host answers with an error. The circuit is closed on failure.
    public static func connect(
        _ circuit: any RelayCircuit, key: NoiseStaticKey, hostKey: Data,
        clientVersion: String, deviceName: String
    ) async throws -> LinkClient {
        try await connect(
            circuit, key: key, hostKey: hostKey, clientVersion: clientVersion, deviceName: deviceName,
            timings: .standard)
    }

    static func connect(
        _ circuit: any RelayCircuit, key: NoiseStaticKey, hostKey: Data,
        clientVersion: String, deviceName: String, timings: LinkTimings
    ) async throws -> LinkClient {
        let watched = WatchedCircuit(circuit)
        let idleTimeout = timings.idleTimeout
        let watchdog = Task { await watched.watch(idleTimeout: idleTimeout) }
        do {
            let channel = try await SecureChannel.open(
                watched, role: .initiator, key: key, trusts: { $0 == hostKey })
            try await channel.send(.hello(clientVersion: clientVersion, deviceName: deviceName))
            try await awaitWelcome(on: channel)
            let client = LinkClient(channel: channel, watchdog: watchdog, timings: timings)
            await client.startReading()
            return client
        } catch {
            watchdog.cancel()
            await watched.close()
            throw error
        }
    }

    /// Asks the host for the full pending set.
    ///
    /// Throws `LinkClientError.timedOut` when no snapshot arrives within the request timeout
    /// (10 s), for example because the host could not fit it in one frame and dropped it
    /// (PROTOCOL.md section 6); the session stays usable. Throws `.sessionClosed` when the session
    /// ends first. Snapshots carry no request id, so a snapshot that arrives after its request
    /// timed out answers the next waiting `snapshot()`; every snapshot is a complete state stamped
    /// with its `revision`, so that answer is still valid.
    public func snapshot() async throws -> (revision: Int, pending: [PendingItem]) {
        try checkOpen()
        let id = makeWaiterId()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Snapshot, any Error>) in
                if let endError {
                    continuation.resume(throwing: endError)
                    return
                }
                snapshotWaiters.append(Waiter(id: id, continuation: continuation, timer: startTimer(for: id)))
                Task { await self.transmit(.snapshotGet, forWaiter: id) }
            }
        } onCancel: {
            Task { await self.failWaiter(id, with: CancellationError()) }
        }
    }

    /// Sends a decision. Safe to repeat: the host answers `already_handled` for a resolved request.
    ///
    /// Throws `LinkClientError.timedOut` when no result arrives within the request timeout (10 s);
    /// the decision may still have been delivered, and repeating it is safe. A result that arrives
    /// after its call timed out (or was cancelled) is dropped, never given to a newer call.
    /// Throws `.sessionClosed` when the session ends first.
    public func reply(requestId: String, mode: PermissionMode) async throws -> ReplyOutcome {
        try checkOpen()
        let id = makeWaiterId()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReplyOutcome, any Error>) in
                if let endError {
                    continuation.resume(throwing: endError)
                    return
                }
                replyWaiters[requestId, default: []].append(
                    Waiter(id: id, continuation: continuation, timer: startTimer(for: id)))
                Task { await self.transmit(.reply(requestId: requestId, mode: mode), forWaiter: id) }
            }
        } onCancel: {
            Task { await self.failWaiter(id, with: CancellationError()) }
        }
    }

    /// Ends the session and closes the circuit. Pending calls throw `LinkClientError.sessionClosed`.
    public func close() async {
        await end(.sessionClosed)
    }

    // MARK: - Session

    private static func awaitWelcome(on channel: SecureChannel) async throws {
        while true {
            let message: LinkMessage
            do {
                message = try await channel.receive()
            } catch LinkCodecError.wrongVersion {
                throw LinkClientError.protocolMismatch(message: "the host sent another protocol version")
            } catch let error as LinkCodecError {
                linkLog.info("client dropped an undecodable frame: \(String(describing: error), privacy: .public)")
                continue
            }
            switch message {
            case let .welcome(protocolVersion, _, _):
                guard protocolVersion == ShellXLink.protocolVersion else {
                    throw LinkClientError.protocolMismatch(message: "the host speaks protocol \(protocolVersion)")
                }
                return
            case let .error(code, text):
                if code == "protocol_mismatch" { throw LinkClientError.protocolMismatch(message: text) }
                throw LinkClientError.rejected(code: code, message: text)
            default:
                // Nothing else is allowed before `welcome`; ignored (PROTOCOL.md section 7).
                continue
            }
        }
    }

    private func startReading() {
        let channel = self.channel
        // Weak, so a client nobody holds any more ends its session (see deinit).
        reader = Task { [weak self] in
            while true {
                let result: Result<LinkMessage, any Error>
                do {
                    result = .success(try await channel.receive())
                } catch {
                    result = .failure(error)
                }
                guard let self else { return }
                guard await self.handle(result) else { return }
            }
        }
    }

    /// Applies one received frame. Returns false when the session is over.
    private func handle(_ result: Result<LinkMessage, any Error>) async -> Bool {
        let message: LinkMessage
        switch result {
        case let .success(received):
            message = received
        case .failure(LinkCodecError.wrongVersion):
            await end(.protocolMismatch(message: "the host sent another protocol version"))
            return false
        case let .failure(error as LinkCodecError):
            linkLog.info("client dropped an undecodable frame: \(String(describing: error), privacy: .public)")
            return true
        case .failure:
            await end(.sessionClosed)
            return false
        }
        switch message {
        case let .snapshot(revision, pending):
            if !snapshotWaiters.isEmpty {
                snapshotWaiters.removeFirst().resume(returning: (revision, pending))
            }
        case let .changed(revision, added, resolved):
            changesContinuation.yield((revision, added, resolved))
        case let .replyResult(requestId, outcome):
            if let late = lateReplyResults[requestId] {
                lateReplyResults[requestId] = late > 1 ? late - 1 : nil
            } else if var waiters = replyWaiters[requestId], !waiters.isEmpty {
                let first = waiters.removeFirst()
                replyWaiters[requestId] = waiters.isEmpty ? nil : waiters
                first.resume(returning: outcome)
            }
        case let .ping(nonce):
            try? await channel.send(.pong(nonce: nonce))
        case let .error(code, text):
            if code == "protocol_mismatch" {
                await end(.protocolMismatch(message: text))
                return false
            }
            linkLog.info("host reported error \(code, privacy: .public)")
        case .pong, .unknown, .hello, .welcome, .snapshotGet, .reply:
            break
        }
        return true
    }

    private func end(_ error: LinkClientError) async {
        guard endError == nil else { return }
        endError = error
        for waiter in snapshotWaiters { waiter.resume(throwing: error) }
        snapshotWaiters = []
        for waiters in replyWaiters.values {
            for waiter in waiters { waiter.resume(throwing: error) }
        }
        replyWaiters = [:]
        lateReplyResults = [:]
        changesContinuation.finish()
        pinger.cancel()
        watchdog.cancel()
        await channel.close()
    }

    private func checkOpen() throws {
        if let endError { throw endError }
        try Task.checkCancellation()
    }

    /// Sends a request whose answer `id` waits for; the waiter fails if the send does.
    private func transmit(_ message: LinkMessage, forWaiter id: Int) async {
        do {
            try await channel.send(message)
        } catch {
            failWaiter(id, with: LinkClientError.sessionClosed)
        }
    }

    private func makeWaiterId() -> Int {
        nextWaiterId += 1
        return nextWaiterId
    }

    /// Fails waiter `id` after `requestTimeout`. Only the waiter times out: the reader keeps its
    /// pending `receive()`, because cancelling that would kill the circuit.
    private func startTimer(for id: Int) -> Task<Void, Never> {
        let timeout = requestTimeout
        return Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            await self?.failWaiter(id, with: LinkClientError.timedOut)
        }
    }

    /// Removes waiter `id` (if it is still waiting) and throws `error` to it.
    private func failWaiter(_ id: Int, with error: any Error) {
        if let index = snapshotWaiters.firstIndex(where: { $0.id == id }) {
            snapshotWaiters.remove(at: index).resume(throwing: error)
            return
        }
        for (requestId, waiters) in replyWaiters {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { continue }
            var rest = waiters
            let waiter = rest.remove(at: index)
            replyWaiters[requestId] = rest.isEmpty ? nil : rest
            // Its `agent.reply` was sent (or the session is ending); the host will still answer it.
            lateReplyResults[requestId, default: 0] += 1
            waiter.resume(throwing: error)
            return
        }
    }
}
