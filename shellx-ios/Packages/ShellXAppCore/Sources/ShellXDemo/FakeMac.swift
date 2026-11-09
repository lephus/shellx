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

    public struct HistoryRequest: Equatable, Sendable {
        public var sessionId: String
        public var beforeSeq: Int?
        public var limit: Int

        public init(sessionId: String, beforeSeq: Int?, limit: Int) {
            self.sessionId = sessionId
            self.beforeSeq = beforeSeq
            self.limit = limit
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

    /// The size of a terminal view a phone opened or resized.
    public struct TerminalViewSize: Equatable, Sendable {
        public var terminalId: String
        public var cols: Int
        public var rows: Int

        public init(terminalId: String, cols: Int, rows: Int) {
            self.terminalId = terminalId
            self.cols = cols
            self.rows = rows
        }
    }

    /// The pairing record a phone keeps for this Mac (its pinned host key is the first one).
    public nonisolated let machine: PairedMachine
    /// False: the host has no session list and no chat, like a ShellX from before agent sessions.
    public nonisolated let servesSessionsAndChat: Bool
    /// False: the chat takes no attachments (no `attachments` feature in `welcome`), like a ShellX
    /// from before them.
    public nonisolated let acceptsAttachments: Bool
    /// False: the host lists no workspaces and takes no workspace control (no `workspaces` or
    /// `workspace_control` feature in `welcome`), like a ShellX from before them.
    public nonisolated let servesWorkspaces: Bool
    /// False: the host lists workspaces but takes no control of them (no `workspace_control` feature).
    public nonisolated let acceptsWorkspaceControl: Bool
    /// False: the host takes no `agent.close` (no `agent_close` feature in `welcome`), like a ShellX from
    /// before it. A host that serves no sessions (`servesSessionsAndChat` false) never advertises it either.
    public nonisolated let acceptsAgentClose: Bool
    /// False: the host takes no `terminal.close` (no `terminal_close` feature in `welcome`), like a ShellX from
    /// before it. A host that serves no workspaces (`servesWorkspaces` false) never advertises it either.
    public nonisolated let acceptsTerminalClose: Bool
    /// False: no `terminal_view` in `welcome` (a ShellX from before it). False too when `servesWorkspaces` is false.
    public nonisolated let servesTerminalViews: Bool
    /// False: no `terminal_create` in `welcome`. False too when `servesWorkspaces` is false.
    public nonisolated let acceptsTerminalCreate: Bool
    /// How many times a phone tried to connect, failed attempts included.
    public private(set) var connectCount = 0

    private var hostKey: NoiseStaticKey
    private let trusted = TrustedPhones()
    private let phoneFrames = FrameCounter()
    private let feed = FakeMacFeed()
    private let sessionSource: FakeMacSessions
    private let workspaceSource: FakeMacWorkspaces
    private let terminals: FakeMacTerminals
    private let chat: FakeMacChat
    private var failure: (any Error)?
    private var failuresLeft = 0
    private var live: [UUID: (circuit: any RelayCircuit, task: Task<Void, Never>)] = [:]

    /// `id` names the Mac (`mac-<id>`) and its slot; a new random one by default. The Debug demo
    /// passes a fixed one, so what the phone keeps about the Mac survives a relaunch.
    public init(
        name: String, id: String? = nil, servesSessionsAndChat: Bool = true, acceptsAttachments: Bool = true,
        servesWorkspaces: Bool = true, acceptsWorkspaceControl: Bool = true, acceptsAgentClose: Bool = true,
        acceptsTerminalClose: Bool = true, servesTerminalViews: Bool = true, acceptsTerminalCreate: Bool = true
    ) {
        let key = NoiseStaticKey()
        hostKey = key
        self.servesSessionsAndChat = servesSessionsAndChat
        self.acceptsAttachments = acceptsAttachments
        self.servesWorkspaces = servesWorkspaces
        self.acceptsWorkspaceControl = acceptsWorkspaceControl
        self.acceptsAgentClose = acceptsAgentClose
        self.acceptsTerminalClose = acceptsTerminalClose
        self.servesTerminalViews = servesWorkspaces && servesTerminalViews
        self.acceptsTerminalCreate = servesWorkspaces && acceptsTerminalCreate
        let sessionSource = FakeMacSessions()
        self.sessionSource = sessionSource
        let workspaceSource = FakeMacWorkspaces(sessions: sessionSource)
        self.workspaceSource = workspaceSource
        terminals = FakeMacTerminals(workspaces: workspaceSource)
        chat = FakeMacChat(acceptsAttachments: acceptsAttachments)
        let id = id ?? UUID().uuidString.lowercased()
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

    /// How many frames phones have sent to this Mac, handshake and every call included, over all circuits.
    /// Frames are encrypted, so this does not say what they hold: a test reads it before and after an
    /// action to show that nothing at all was sent, which `agentCloses` cannot, because a Mac that does
    /// not advertise `agent_close` has no agent control to count a call.
    public nonisolated var phoneFrameCount: Int { phoneFrames.count }

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
            workspaces: servesWorkspaces ? workspaceSource : nil,
            workspaceControl: servesWorkspaces && acceptsWorkspaceControl ? workspaceSource : nil,
            agentControl: servesSessionsAndChat && acceptsAgentClose ? workspaceSource : nil,
            terminalControl: servesWorkspaces && acceptsTerminalClose ? workspaceSource : nil,
            terminalViews: servesTerminalViews ? terminals : nil,
            terminalCreator: acceptsTerminalCreate ? terminals : nil,
            hostVersion: "fake", machineName: machine.name)
        let id = UUID()
        live[id] = (macEnd, Task {
            await host.serve(macEnd)
            self.ended(id)
        })
        return CountingCircuit(phoneEnd, counter: phoneFrames)
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

    // MARK: - Workspaces

    /// The Mac's workspaces become `workspaces`; phones get what differs as one change.
    public func setWorkspaces(_ workspaces: [LinkWorkspace]) { workspaceSource.set(workspaces) }
    public func upsertWorkspace(_ workspace: LinkWorkspace) { workspaceSource.upsert(workspace) }
    public func removeWorkspace(_ workspaceId: String) { workspaceSource.remove(workspaceId) }
    /// The next workspace change arrives one revision too far, so the phone sees a gap.
    public func skipNextWorkspaceRevision() { workspaceSource.skipRevision() }
    /// How many `workspace.list.get` the Mac answered.
    public var workspaceListCount: Int { workspaceSource.listCount }
    /// Every control call the Mac received, in order: `create`, `rename:<id>:<title>`, `close:<id>`.
    public var workspaceCalls: [String] { workspaceSource.controlCalls }
    /// The next control call answers `outcome` and, unless it is `ok`, changes nothing. Without it the
    /// Mac acts as the real one does: it makes the workspace, renames or closes one it has (`not_found`
    /// otherwise) and keeps its last workspace (`refused`).
    public func setNextWorkspaceOutcome(_ outcome: WorkspaceControlOutcome) { workspaceSource.setNextOutcome(outcome) }
    /// From now on control calls are recorded but not answered until `releaseWorkspaceControl()`, as
    /// when the Mac is slow.
    public func holdWorkspaceControl() { workspaceSource.hold() }
    public func releaseWorkspaceControl() { workspaceSource.release() }
    /// The session id of every `agent.close` the Mac received, in order. Held and released with the
    /// workspace control calls (`holdWorkspaceControl()`).
    public var agentCloses: [String] { workspaceSource.agentCloses }
    /// The next `agent.close` answers `outcome` and, unless it is `ok`, changes nothing. Without it the Mac
    /// acts as the real one does: a session it lists that has not ended turns `.ended` (`ok`), any other id
    /// is `not_found`.
    public func setNextAgentCloseOutcome(_ outcome: WorkspaceControlOutcome) { workspaceSource.setNextAgentCloseOutcome(outcome) }
    /// The workspace id and terminal id of every `terminal.close` the Mac received, in order. Held and
    /// released with the workspace control calls (`holdWorkspaceControl()`).
    public var terminalCloses: [(workspaceId: String, terminalId: String)] { workspaceSource.terminalCloses }
    /// The next `terminal.close` answers `outcome` and, unless it is `ok`, changes nothing. Without it the Mac
    /// acts as the real one does: a terminal that the named workspace lists is closed (`ok`), and the
    /// workspace goes with its last terminal; any other pair is `not_found`.
    public func setNextTerminalCloseOutcome(_ outcome: WorkspaceControlOutcome) { workspaceSource.setNextTerminalCloseOutcome(outcome) }

    // MARK: - Terminal views

    /// What a view of each terminal shows, by terminal id; any other listed terminal shows a fresh
    /// `DemoTerminalScreens.prompt(cols:rows:)` at the size the phone asked for. Views opened later use them.
    public func setTerminalFixtures(_ fixtures: [String: DemoTerminalFixture]) { terminals.setFixtures(fixtures) }
    /// From now on opening a view of `terminalId` answers `outcome`.
    public func refuseTerminalView(_ terminalId: String, with outcome: TerminalViewOpenOutcome) {
        terminals.refuse(terminalId, with: outcome)
    }
    /// From now on view opens are recorded but not answered until `releaseTerminalViewOpens()`.
    public func holdTerminalViewOpens() { terminals.hold() }
    public func releaseTerminalViewOpens() { terminals.release() }
    /// `frame` goes to the phone viewing `terminalId`, before anything the fake shell made.
    public func emitTerminalFrame(_ terminalId: String, _ frame: TerminalGridFrame) { terminals.emit(terminalId, .frame(frame)) }
    /// The current view of `terminalId` ends with `reason`.
    public func endTerminalView(_ terminalId: String, reason: TerminalViewEndReason) {
        terminals.emit(terminalId, .ended(reason))
    }
    /// The next `terminal.create` answers `outcome` and, unless it is `ok`, changes nothing. Without it the Mac adds a
    /// terminal `<workspaceId>-new-<n>` to a workspace it lists (`not_found` otherwise).
    public func setNextTerminalCreateOutcome(_ outcome: WorkspaceControlOutcome) { terminals.setNextCreateOutcome(outcome) }
    /// Every view open the Mac received, in order (refused ones too).
    public var terminalViewOpens: [TerminalViewSize] { terminals.viewOpens }
    public var terminalViewResizes: [TerminalViewSize] { terminals.viewResizes }
    /// The terminal id of every view closed, in order.
    public var terminalViewCloses: [String] { terminals.viewCloses }
    /// The units of every `terminal.view.input` a view of `terminalId` applied, in order.
    public func terminalViewInputs(_ terminalId: String) -> [[TerminalInputUnit]] { terminals.viewInputs(terminalId) }
    /// How many snapshots views of `terminalId` were asked for (resyncs).
    public func terminalViewSnapshotRequests(_ terminalId: String) -> Int { terminals.viewSnapshotRequests(terminalId) }
    /// The workspace id of every `terminal.create`, in order.
    public var terminalCreates: [String] { terminals.createCalls }

    // MARK: - Chat

    public func setHistory(sessionId: String, entries: [ChatEntry]) { chat.setHistory(sessionId: sessionId, entries: entries) }
    public func pushChat(sessionId: String, entries: [ChatEntry]) { chat.push(sessionId: sessionId, entries: entries) }
    /// The Mac reloads the session's transcript (its `seq` values start over): the transcript
    /// becomes `entries` and phones get `chat.reset`, in order with the session's pushes.
    public func resetChat(sessionId: String, entries: [ChatEntry]) { chat.reset(sessionId: sessionId, entries: entries) }
    /// nil goes back to `submitted` for a known session and `not_found` otherwise.
    public func setSendOutcome(_ outcome: ChatSendOutcome?) { chat.setSendOutcome(outcome) }
    public var sentTexts: [SentText] { chat.sentTexts }
    /// The attachments of every message the Mac took, in order (their messages are in `sentTexts`).
    public var receivedAttachments: [ChatAttachment] { chat.receivedAttachments }
    /// nil goes back to `sent` for a known session and `not_found` otherwise.
    public func setInterruptOutcome(_ outcome: ChatInterruptOutcome?) { chat.setInterruptOutcome(outcome) }
    public var interrupts: [Interrupt] { chat.interrupts }
    /// Every `chat.history.get` the Mac received, in order.
    public var historyRequests: [HistoryRequest] { chat.historyRequests }
    /// From now on chat calls (history, send, interrupt) are recorded but not answered until
    /// `releaseChat()`, as when the Mac is slow.
    public func holdChat() { chat.hold() }
    public func releaseChat() { chat.release() }
}

/// Counts the frames a phone sends; read from any thread.
private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0

    var count: Int { lock.withLock { frames } }

    func add() {
        lock.withLock { frames += 1 }
    }
}

/// The phone's end of a circuit, counting what the phone sends.
private struct CountingCircuit: RelayCircuit {
    let inner: any RelayCircuit
    let counter: FrameCounter

    init(_ inner: any RelayCircuit, counter: FrameCounter) {
        self.inner = inner
        self.counter = counter
    }

    func send(_ data: Data) async throws {
        counter.add()
        try await inner.send(data)
    }

    func receive() async throws -> Data { try await inner.receive() }
    func close() async { await inner.close() }
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
