import Foundation
import ShellXLinkCore
import ShellXLinkRelay

/// The Mac (or PC) side of ShellX Link: serves the agent feed to trusted phones.
///
/// One `LinkHost` serves any number of circuits at once; each `serve` call is one session.
/// Session state lives in `serve`, so the actor holds only configuration.
public actor LinkHost {
    private nonisolated let key: NoiseStaticKey
    private nonisolated let trustedClients: @Sendable () -> Set<Data>
    private nonisolated let feed: any AgentFeedSource
    private nonisolated let hostVersion: String
    private nonisolated let machineName: String
    private nonisolated let timings: LinkTimings

    /// - Parameter trustedClients: the paired phones' static public keys, read on every handshake.
    public init(
        key: NoiseStaticKey, trustedClients: @escaping @Sendable () -> Set<Data>,
        feed: any AgentFeedSource, hostVersion: String, machineName: String
    ) {
        self.init(
            key: key, trustedClients: trustedClients, feed: feed, hostVersion: hostVersion,
            machineName: machineName, timings: .standard)
    }

    init(
        key: NoiseStaticKey, trustedClients: @escaping @Sendable () -> Set<Data>,
        feed: any AgentFeedSource, hostVersion: String, machineName: String, timings: LinkTimings
    ) {
        self.key = key
        self.trustedClients = trustedClients
        self.feed = feed
        self.hostVersion = hostVersion
        self.machineName = machineName
        self.timings = timings
    }

    /// Runs one session on `circuit` and returns when it ends. The circuit is closed on return.
    ///
    /// Flow: Noise handshake (responder), `hello` -> `welcome`, then `agent.changed` pushes for
    /// every feed change and answers to `agent.snapshot.get`, `agent.reply` and `ping`.
    /// Cancelling the calling task ends the session.
    public func serve(_ circuit: any RelayCircuit) async {
        await runSession(circuit)
    }

    private nonisolated func runSession(_ circuit: any RelayCircuit) async {
        let watched = WatchedCircuit(circuit)
        await withDiscardingTaskGroup { group in
            group.addTask { await watched.watch(idleTimeout: self.timings.idleTimeout) }
            await self.converse(on: watched, group: &group)
            // Close first so that child tasks blocked on the circuit fail fast, then stop the rest.
            await watched.close()
            group.cancelAll()
        }
    }

    /// The session itself. Returns when the session must end.
    private nonisolated func converse(on circuit: WatchedCircuit, group: inout DiscardingTaskGroup) async {
        let trustedClients = self.trustedClients
        let channel: SecureChannel
        do {
            channel = try await SecureChannel.open(
                circuit, role: .responder, key: key, trusts: { trustedClients().contains($0) })
        } catch {
            linkLog.info("host handshake failed: \(String(describing: error), privacy: .public)")
            return
        }

        // Pre-hello: the first frame must be `hello` (PROTOCOL.md section 7).
        let first: LinkMessage
        do {
            first = try await channel.receive()
        } catch LinkCodecError.wrongVersion {
            await Self.sendError(on: channel, "protocol_mismatch", "this host speaks ShellX Link protocol 1")
            return
        } catch is LinkCodecError {
            await Self.sendError(on: channel, "bad_request", "the first frame must be hello")
            return
        } catch {
            return
        }
        guard case .hello = first else {
            await Self.sendError(on: channel, "bad_request", "the first frame must be hello")
            return
        }

        // Subscribe before `welcome`, so no change after it is missed: the stream buffers until the
        // pusher starts. Leaving the scope without iterating it drops the subscription.
        let changes = feed.changes()
        do {
            try await channel.send(.welcome(
                protocolVersion: ShellXLink.protocolVersion, hostVersion: hostVersion, machineName: machineName))
        } catch {
            return
        }
        // Only now: nothing but `welcome` (or `error`) may precede establishment (PROTOCOL.md 7).
        // The subscription ends when the group cancels this task at the end of the session.
        group.addTask {
            for await change in changes {
                await Self.sendShrinking(on: channel, items: change.added) {
                    .changed(revision: change.revision, added: $0, resolved: change.resolved)
                }
            }
        }
        let pingInterval = timings.pingInterval
        group.addTask { await runPings(on: channel, every: pingInterval) }

        // Established.
        let feed = self.feed
        let replyOrder = ReplyOrder()
        while true {
            let message: LinkMessage
            do {
                message = try await channel.receive()
            } catch LinkCodecError.wrongVersion {
                await Self.sendError(on: channel, "protocol_mismatch", "this host speaks ShellX Link protocol 1")
                return
            } catch is LinkCodecError {
                await Self.sendError(on: channel, "bad_request", "the frame could not be decoded")
                continue
            } catch {
                return
            }
            switch message {
            case .snapshotGet:
                // Answered in order, so snapshot replies follow the order of the requests.
                let snapshot = await feed.snapshot()
                await Self.sendShrinking(on: channel, items: snapshot.pending) {
                    .snapshot(revision: snapshot.revision, pending: $0)
                }
            case let .reply(requestId, mode):
                // Resolving may wait on the agent hook; keep reading meanwhile. Replies to one
                // request run one after another in arrival order, so their results leave in the
                // order the client sent them (it matches a result to the oldest reply for that
                // id). Replies to different requests run concurrently.
                let turn = await replyOrder.reserve(requestId)
                group.addTask {
                    await replyOrder.wait(for: turn, of: requestId)
                    let outcome = await feed.reply(requestId: requestId, mode: mode)
                    try? await channel.send(.replyResult(requestId: requestId, outcome: outcome))
                    await replyOrder.finish(turn, of: requestId)
                }
            case let .ping(nonce):
                try? await channel.send(.pong(nonce: nonce))
            case .pong, .unknown, .error:
                break
            case .hello, .welcome, .snapshot, .changed, .replyResult:
                // Not allowed from a client once established: ignored, and answered (PROTOCOL.md 7).
                await Self.sendError(on: channel, "bad_request", "unexpected frame from a client")
            }
        }
    }

    private static func sendError(on channel: SecureChannel, _ code: String, _ message: String) async {
        try? await channel.send(.error(code: code, message: message))
    }

    /// Sends a message built from `items`, shrinking previews when the frame is too large.
    private static func sendShrinking(
        on channel: SecureChannel, items: [PendingItem], _ make: ([PendingItem]) -> LinkMessage
    ) async {
        guard let frame = shrunkFrame(items: items, make) else {
            linkLog.error("dropping a frame that does not fit even without previews (\(items.count) items)")
            return
        }
        try? await channel.send(frame: frame)
    }

    /// PROTOCOL.md section 6: previews cut to 8192 bytes, then 1024, then omitted; the first
    /// encoding that fits wins. Nil when none fits.
    static func shrunkFrame(items: [PendingItem], _ make: ([PendingItem]) -> LinkMessage) -> Data? {
        let limits: [Int?] = [PendingItem.maxPreviewBytes, 1024, nil]
        for limit in limits {
            do {
                return try LinkCodec.encode(make(items.map { $0.withPreviewLimit(limit) }))
            } catch LinkCodecError.frameTooLarge {
                continue
            } catch {
                linkLog.error("cannot encode a host frame: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        return nil
    }
}

/// Per-`request_id` FIFO turns for one session's `agent.reply` handlers.
///
/// The receive loop reserves a turn when the frame arrives; the handler waits for that turn,
/// and finishing it (after its result was sent) lets the next reply for the same id run.
private actor ReplyOrder {
    /// The next turn to hand out, per id. Absent when no reply for that id is in flight.
    private var nextTurn: [String: Int] = [:]
    /// The turn that may run now, per id.
    private var current: [String: Int] = [:]
    private var waiting: [String: [Int: CheckedContinuation<Void, Never>]] = [:]

    func reserve(_ requestId: String) -> Int {
        let turn = nextTurn[requestId, default: 0]
        nextTurn[requestId] = turn + 1
        return turn
    }

    func wait(for turn: Int, of requestId: String) async {
        guard current[requestId, default: 0] != turn else { return }
        await withCheckedContinuation { waiting[requestId, default: [:]][turn] = $0 }
    }

    func finish(_ turn: Int, of requestId: String) {
        let following = turn + 1
        guard nextTurn[requestId] != following else {
            // Nothing else queued for this id.
            nextTurn[requestId] = nil
            current[requestId] = nil
            waiting[requestId] = nil
            return
        }
        current[requestId] = following
        if let next = waiting[requestId]?.removeValue(forKey: following) {
            next.resume()
        }
    }
}
