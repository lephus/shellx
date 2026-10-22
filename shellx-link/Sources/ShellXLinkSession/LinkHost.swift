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

        // Subscribe before `welcome`, so no change after it is missed. The subscription ends when
        // the group cancels this task at the end of the session.
        let changes = feed.changes()
        group.addTask {
            for await change in changes {
                await Self.sendShrinking(on: channel, items: change.added) {
                    .changed(revision: change.revision, added: $0, resolved: change.resolved)
                }
            }
        }
        do {
            try await channel.send(.welcome(
                protocolVersion: ShellXLink.protocolVersion, hostVersion: hostVersion, machineName: machineName))
        } catch {
            return
        }
        let pingInterval = timings.pingInterval
        group.addTask { await runPings(on: channel, every: pingInterval) }

        // Established.
        let feed = self.feed
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
                // Resolving may wait on the agent hook; keep reading meanwhile.
                group.addTask {
                    let outcome = await feed.reply(requestId: requestId, mode: mode)
                    try? await channel.send(.replyResult(requestId: requestId, outcome: outcome))
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
