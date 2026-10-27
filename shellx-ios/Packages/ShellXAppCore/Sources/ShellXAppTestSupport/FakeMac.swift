import Foundation
import ShellXAppCore
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession

/// A Mac running ShellX, in process: a real `LinkHost` (Noise handshake, protocol, revisions) over
/// fake agent sources, reached through `makeInMemoryCircuitPair()` instead of the relay.
///
/// Every connect opens a new `LinkHost` session with the Mac's current key and options, so
/// `rotateHostKey()` and `failNextConnects(_:count:)` take effect on the next attempt.
public actor FakeMac {
    public struct Decision: Equatable, Sendable {
        public var requestId: String
        public var decision: LinkDecision

        public init(requestId: String, decision: LinkDecision) {
            self.requestId = requestId
            self.decision = decision
        }
    }

    public struct SentText: Equatable, Sendable {
        public var sessionId: String
        public var text: String

        public init(sessionId: String, text: String) {
            self.sessionId = sessionId
            self.text = text
        }
    }

    public struct Interrupt: Equatable, Sendable {
        public var sessionId: String
        public var hard: Bool

        public init(sessionId: String, hard: Bool) {
            self.sessionId = sessionId
            self.hard = hard
        }
    }

    /// The pairing record a phone keeps for this Mac (its pinned host key is the first one).
    public nonisolated let machine: PairedMachine
    /// False: the host has no session list and no chat, like a ShellX from before agent sessions.
    public nonisolated let servesSessionsAndChat: Bool
    /// How many times a phone tried to connect, failed attempts included.
    public private(set) var connectCount = 0

    private var hostKey: NoiseStaticKey
    private let trusted = TrustedPhones()
    private let feed = FakeMacFeed()
    private let sessionSource = FakeMacSessions()
    private let chat = FakeMacChat()
    private var failure: (any Error)?
    private var failuresLeft = 0
    private var live: [UUID: (circuit: any RelayCircuit, task: Task<Void, Never>)] = [:]

    public init(name: String, servesSessionsAndChat: Bool = true) {
        let key = NoiseStaticKey()
        hostKey = key
        self.servesSessionsAndChat = servesSessionsAndChat
        let id = UUID().uuidString.lowercased()
        machine = PairedMachine(
            machineID: "mac-\(id)", name: name, linkSlot: "slot-\(id)", hostKey: key.publicKey)
    }

    /// A connector to this Mac for a phone whose Link key `phoneKey` returns. The Mac trusts that
    /// key, as after pairing.
    public nonisolated func connector(
        phoneKey: @escaping @Sendable () async throws -> NoiseStaticKey
    ) -> any MachineLinkConnecting {
        FakeMacConnector(mac: self, phoneKey: phoneKey)
    }

    // MARK: - Connections

    /// The next `count` connects throw `error` (before any handshake), as the relay or network would.
    public func failNextConnects(_ error: any Error, count: Int) {
        failure = error
        failuresLeft = count
    }

    /// The Mac gets a new key: phones that pinned the old one refuse the handshake.
    public func rotateHostKey() {
        hostKey = NoiseStaticKey()
    }

    /// Ends every live session from the Mac's side, as a dropped network would.
    public func dropLiveSessions() async {
        let sessions = Array(live.values)
        for session in sessions { await session.circuit.close() }
        for session in sessions { await session.task.value }
    }

    /// The QR code the Mac would show now: its current host key and a new one-time code.
    public func pairingOffer() -> PairingOffer {
        PairingOffer.make(
            machineID: machine.machineID, linkSlot: machine.linkSlot, hostKey: hostKey.publicKey,
            machineName: machine.name)
    }

    /// `pairingOffer().uri`: what scanning the Mac's QR code (or copying its code) gives.
    public func pairingCode() -> String { pairingOffer().uri }

    /// How many sessions are being served right now.
    public var liveSessionCount: Int { live.count }

    /// Opens the Mac's end of a new circuit and serves it; returns the phone's end.
    fileprivate func open(phoneKey: Data) throws -> any RelayCircuit {
        connectCount += 1
        if failuresLeft > 0, let failure {
            failuresLeft -= 1
            throw failure
        }
        trusted.insert(phoneKey)
        let (phoneEnd, macEnd) = makeInMemoryCircuitPair()
        let trusted = self.trusted
        let host = LinkHost(
            key: hostKey, trustedClients: { trusted.keys }, feed: feed,
            sessions: servesSessionsAndChat ? sessionSource : nil, chat: servesSessionsAndChat ? chat : nil,
            hostVersion: "fake", machineName: machine.name)
        let id = UUID()
        live[id] = (macEnd, Task {
            await host.serve(macEnd)
            self.ended(id)
        })
        return phoneEnd
    }

    private func ended(_ id: UUID) {
        live[id] = nil
    }

    // MARK: - Pending

    public func addPending(_ item: PendingItem) { feed.add(item) }
    public func resolvePending(_ requestId: String) { feed.resolve(requestId) }
    /// The next pending change arrives one revision too far, so the phone sees a gap.
    public func skipNextPendingRevision() { feed.skipRevision() }
    /// Every reply waits `delay`, then answers `outcome`; nil goes back to answering from the pending
    /// set. `.delivered` also resolves the item, unless `resolves` is false: then the Mac's
    /// `agent.changed` waits for `resolvePending(_:)`, as when it arrives after the reply's result.
    public func setReplyOutcome(_ outcome: ReplyOutcome?, delay: Duration = .zero, resolves: Bool = true) {
        feed.setReplyOutcome(outcome, delay: delay, resolves: resolves)
    }
    public var decisions: [Decision] { feed.decisions }
    /// How many `agent.snapshot.get` the Mac answered.
    public var snapshotCount: Int { feed.snapshotCount }
    /// From now on `agent.snapshot.get` is not answered (the phone stays connected but unsynced)
    /// until `releaseSnapshots()`.
    public func holdSnapshots() { feed.holdSnapshots() }
    public func releaseSnapshots() { feed.releaseSnapshots() }
    /// How many snapshot requests are being held.
    public var heldSnapshotCount: Int { feed.heldSnapshotCount }

    // MARK: - Sessions

    public func upsertSession(_ session: AgentSession) { sessionSource.upsert(session) }
    public func removeSession(_ sessionId: String) { sessionSource.remove(sessionId) }
    /// The next session change arrives one revision too far, so the phone sees a gap.
    public func skipNextSessionRevision() { sessionSource.skipRevision() }
    /// How many `agent.sessions.get` the Mac answered.
    public var sessionListCount: Int { sessionSource.listCount }

    // MARK: - Chat

    public func setHistory(sessionId: String, entries: [ChatEntry]) { chat.setHistory(sessionId: sessionId, entries: entries) }
    public func pushChat(sessionId: String, entries: [ChatEntry]) { chat.push(sessionId: sessionId, entries: entries) }
    /// nil goes back to `submitted` for a known session and `not_found` otherwise.
    public func setSendOutcome(_ outcome: ChatSendOutcome?) { chat.setSendOutcome(outcome) }
    public var sentTexts: [SentText] { chat.sentTexts }
    /// nil goes back to `sent` for a known session and `not_found` otherwise.
    public func setInterruptOutcome(_ outcome: ChatInterruptOutcome?) { chat.setInterruptOutcome(outcome) }
    public var interrupts: [Interrupt] { chat.interrupts }
}

/// The phone keys a `FakeMac` trusts; read by `LinkHost` on every handshake, from any thread.
private final class TrustedPhones: @unchecked Sendable {
    private let lock = NSLock()
    private var set: Set<Data> = []

    var keys: Set<Data> { lock.withLock { set } }

    func insert(_ key: Data) {
        _ = lock.withLock { set.insert(key) }
    }
}

private struct FakeMacConnector: MachineLinkConnecting {
    let mac: FakeMac
    let phoneKey: @Sendable () async throws -> NoiseStaticKey

    func connect(_ machine: PairedMachine) async throws -> LinkClient {
        let key = try await phoneKey()
        let circuit = try await mac.open(phoneKey: key.publicKey)
        return try await LinkClient.connect(
            circuit, key: key, hostKey: machine.hostKey, clientVersion: "2.0.0", deviceName: "Test iPhone")
    }
}
