import Foundation
import Observation
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkSession
import os

/// Every paired Mac and its Link, for the signed-in account: one `MachineConnection` per Mac, the
/// merged pending items and live sessions, and the calls that act on them.
///
/// The hub is the only writer of the vault's Mac list: `start()` reads it, `add(_:)` writes it.
@MainActor @Observable
public final class MachineHub {
    /// How long sessions stay open after the app went to the background.
    public static let backgroundGrace: Duration = .seconds(25)
    static let defaultMachineKey = "shellx.defaultMachineID"

    public private(set) var machines: [MachineModel] = []
    private var storedDefaultMachineID: String?

    @ObservationIgnored private let vault: AccountVault
    @ObservationIgnored private let relay: any RelayAccountCalling
    @ObservationIgnored private let connector: any MachineLinkConnecting
    @ObservationIgnored private let latency: LatencyLog
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let onUnauthorized: @MainActor () async -> Void
    @ObservationIgnored private let log = Logger(subsystem: "com.shellx.app", category: "link")

    /// The vault's Mac list as last read or written.
    @ObservationIgnored private var records: [PairedMachine] = []
    @ObservationIgnored private var connections: [String: MachineConnection] = [:]
    @ObservationIgnored private var readers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var chatSubscribers: [UUID: AsyncStream<(SessionRef, [ChatEntry])>.Continuation] = [:]
    @ObservationIgnored private var sessionSubscribers:
        [UUID: AsyncStream<(machineID: String, sessions: [AgentSession])>.Continuation] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var stopped = false
    /// The app is in the background (until `appDidBecomeActive()`).
    @ObservationIgnored private var inBackground = false
    /// The sessions were closed because the app stayed in the background past the grace.
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var grace: Task<Bool, Never>?
    @ObservationIgnored private var unauthorizedReported = false

    public init(
        vault: AccountVault, relay: any RelayAccountCalling, connector: any MachineLinkConnecting,
        latency: LatencyLog, defaults: UserDefaults, sleep: @escaping @Sendable (Duration) async throws -> Void,
        onUnauthorized: @escaping @MainActor () async -> Void
    ) {
        self.vault = vault
        self.relay = relay
        self.connector = connector
        self.latency = latency
        self.defaults = defaults
        self.sleep = sleep
        self.onUnauthorized = onUnauthorized
        storedDefaultMachineID = defaults.string(forKey: Self.defaultMachineKey)
    }

    // MARK: - What the UI reads

    /// The Mac new messages go to when nothing else picks one: the chosen one while it is paired,
    /// otherwise the first Mac. Kept in `UserDefaults` under `shellx.defaultMachineID`.
    public var defaultMachineID: String? {
        get {
            if let id = storedDefaultMachineID, machines.contains(where: { $0.id == id }) { return id }
            return machines.first?.id
        }
        set {
            storedDefaultMachineID = newValue
            defaults.set(newValue, forKey: Self.defaultMachineKey)
        }
    }

    /// Every Mac's pending requests, oldest first.
    public var pendingItems: [MachinePendingItem] {
        machines.flatMap { model in
            model.pending.items.map {
                MachinePendingItem(
                    machineID: model.id, machineName: model.name, item: $0, actionable: model.pendingActionable)
            }
        }
        .sorted { ($0.item.createdAtMs, $0.machineID, $0.item.requestId) < ($1.item.createdAtMs, $1.machineID, $1.item.requestId) }
    }

    /// Every session that has not ended, on every Mac, most recent activity first. An offline Mac's
    /// sessions are its last known ones, with `online` false.
    public var liveSessions: [MachineSession] {
        machines.flatMap { model in
            model.sessions.sessions.filter { $0.state != .ended }.map {
                MachineSession(machineID: model.id, machineName: model.name, online: model.state == .online, session: $0)
            }
        }
        .sorted { a, b in
            let (lhs, rhs) = (a.session.lastActivityMs ?? .min, b.session.lastActivityMs ?? .min)
            return lhs != rhs ? lhs > rhs : (a.machineID, a.session.sessionId) < (b.machineID, b.session.sessionId)
        }
    }

    // MARK: - Lifecycle

    /// Reads the paired Macs from the vault and connects to each. Runs once.
    public func start() async {
        guard !started, !stopped else { return }
        started = true
        do {
            records = try await vault.machines()
        } catch {
            log.error("hub_machines_unreadable")
        }
        guard !stopped else { return }
        for machine in records where !machines.contains(where: { $0.id == machine.machineID }) {
            let model = MachineModel(machine: machine)
            machines.append(model)
            connect(model)
        }
    }

    /// Stops every connection and finishes the update streams. The hub is done afterwards.
    public func stopAll() async {
        stopped = true
        grace?.cancel()
        grace = nil
        for reader in readers.values { reader.cancel() }
        readers = [:]
        let all = Array(connections.values)
        connections = [:]
        for connection in all { await connection.stop() }
        for continuation in chatSubscribers.values { continuation.finish() }
        for continuation in sessionSubscribers.values { continuation.finish() }
        chatSubscribers = [:]
        sessionSubscribers = [:]
        for model in machines { model.pendingActionable = false }
    }

    /// Saves a newly paired Mac (owned by the signed-in account) and connects to it. A Mac already
    /// paired under the same `machineID` is replaced.
    public func add(_ machine: PairedMachine) async throws {
        if !started { await start() }
        guard !stopped, let owner = try await vault.session()?.userID else { throw AddError.notSignedIn }
        // The list changes before the write, so overlapping adds each write every Mac.
        let old = records.first { $0.machineID == machine.machineID }
        Self.upsert(machine, into: &records)
        do {
            try await vault.setMachines(records, owner: owner)
        } catch {
            if let old {
                Self.upsert(old, into: &records)
            } else {
                records.removeAll { $0.machineID == machine.machineID }
            }
            throw error
        }
        guard !stopped else { return }
        if let model = machines.first(where: { $0.id == machine.machineID }) {
            await disconnect(model)
            model.replace(with: machine)
            connect(model)
        } else {
            let model = MachineModel(machine: machine)
            machines.append(model)
            connect(model)
        }
    }

    /// Asks the relay which Macs this iPhone may still reach: a Mac missing from the list becomes
    /// `.revoked` (its connection stops), and a renamed Mac takes its new name. A 401 signs out.
    public func refreshGrants() async {
        guard !stopped else { return }
        let token: String
        do {
            guard let stored = try await vault.session()?.token else { return }
            token = stored
        } catch {
            return
        }
        let known = machines
        let grants: [PairedMachineListing]
        do {
            grants = try await relay.machines(token: token)
        } catch {
            if LinkFailure(error) == .signedOut { await reportUnauthorized() }
            return
        }
        guard !stopped else { return }
        let byID = Dictionary(grants.map { ($0.machineID, $0) }, uniquingKeysWith: { first, _ in first })
        // Only Macs that were there before the request: one added meanwhile may not be listed yet.
        for model in known where machines.contains(where: { $0 === model }) {
            if let grant = byID[model.id] {
                if model.name != grant.name { model.name = grant.name }
            } else if model.state != .revoked {
                await revoke(model)
            }
        }
    }

    public func appDidBecomeActive() {
        inBackground = false
        grace?.cancel()
        grace = nil
        guard !stopped else { return }
        if suspended {
            resume()
            return
        }
        // Coming back is a good moment to retry a Mac that was out of reach.
        for model in machines where model.state != .online {
            guard let connection = connections[model.id] else { continue }
            Task { await connection.reconnectNow() }
        }
    }

    /// Waits `backgroundGrace`; when the app is still in the background then, closes every session.
    /// Returns early when the app comes back. The app calls it inside a background task.
    public func appDidEnterBackground() async {
        guard !stopped else { return }
        inBackground = true
        grace?.cancel()
        let sleep = self.sleep
        let wait = Task { () -> Bool in
            do {
                try await sleep(Self.backgroundGrace)
                return !Task.isCancelled
            } catch {
                return false
            }
        }
        grace = wait
        let elapsed = await wait.value
        guard elapsed, inBackground, grace == wait, !stopped else { return }
        grace = nil
        await suspend()
    }

    /// The network path changed (Wi-Fi to cellular, a new Wi-Fi, back online): a live session may be
    /// dead without anyone knowing yet, so it is replaced at once, and the others retry now.
    public func networkChanged() {
        guard !stopped, !suspended else { return }
        for model in machines {
            guard let connection = connections[model.id] else { continue }
            if model.state == .online {
                Task { await connection.forceReconnect() }
            } else {
                Task { await connection.reconnectNow() }
            }
        }
    }

    // MARK: - Calls

    public func reply(_ key: PendingKey, decision: LinkDecision) async throws -> ReplyOutcome {
        let start = ContinuousClock.now
        let outcome = try await withLink(key.machineID) {
            try await $0.reply(requestId: key.requestId, decision: decision)
        }
        latency.record(.replyRoundTrip, ContinuousClock.now - start)
        return outcome
    }

    public func chatHistory(
        _ ref: SessionRef, beforeSeq: Int?, limit: Int
    ) async throws -> (entries: [ChatEntry], hasMore: Bool) {
        try await withLink(ref.machineID) {
            try await $0.chatHistory(sessionId: ref.sessionId, beforeSeq: beforeSeq, limit: limit)
        }
    }

    public func chatSend(_ ref: SessionRef, text: String) async throws -> ChatSendOutcome {
        try await withLink(ref.machineID) { try await $0.chatSend(sessionId: ref.sessionId, text: text) }
    }

    public func chatInterrupt(_ ref: SessionRef, hard: Bool) async throws -> ChatInterruptOutcome {
        try await withLink(ref.machineID) { try await $0.chatInterrupt(sessionId: ref.sessionId, hard: hard) }
    }

    /// Chat entries from every Mac as they arrive. Each call adds a subscriber, dropped when its
    /// reader stops. Nothing is kept for a later subscriber.
    public func chatUpdates() -> AsyncStream<(SessionRef, [ChatEntry])> {
        let (stream, continuation) = AsyncStream.makeStream(of: (SessionRef, [ChatEntry]).self)
        let id = UUID()
        chatSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.chatSubscribers[id] = nil }
        }
        return stream
    }

    /// Each Mac's session list whenever it changes. Multicast like `chatUpdates()`.
    public func sessionUpdates() -> AsyncStream<(machineID: String, sessions: [AgentSession])> {
        let (stream, continuation) = AsyncStream.makeStream(of: (machineID: String, sessions: [AgentSession]).self)
        let id = UUID()
        sessionSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.sessionSubscribers[id] = nil }
        }
        return stream
    }

    var chatSubscriberCount: Int { chatSubscribers.count }
    var sessionSubscriberCount: Int { sessionSubscribers.count }

    // MARK: - Connections

    private func connect(_ model: MachineModel) {
        if let old = connections[model.id] {
            readers[model.id]?.cancel()
            Task { await old.stop() }
        }
        let connection = MachineConnection(machine: model.machine, connector: connector, latency: latency, sleep: sleep)
        connections[model.id] = connection
        readers[model.id] = Task { [weak self] in
            for await event in connection.events {
                guard let self else { return }
                self.apply(event, from: connection, to: model)
            }
        }
        Task { await connection.start() }
    }

    private func disconnect(_ model: MachineModel) async {
        readers.removeValue(forKey: model.id)?.cancel()
        if let connection = connections.removeValue(forKey: model.id) { await connection.stop() }
    }

    private func apply(_ event: MachineEvent, from connection: MachineConnection, to model: MachineModel) {
        // A connection that was replaced or stopped no longer speaks for the Mac.
        guard connections[model.id] === connection else { return }
        switch event {
        case let .state(state):
            model.state = state
        case let .pending(set, actionable):
            model.pending = set
            model.pendingActionable = actionable
        case let .sessions(set, supported):
            model.sessions = set
            model.sessionsSupported = supported
            for (id, continuation) in sessionSubscribers {
                if case .terminated = continuation.yield((model.id, set.sessions)) { sessionSubscribers[id] = nil }
            }
        case let .chat(sessionId, entries):
            guard !chatSubscribers.isEmpty else { return }
            let session = model.sessions.session(sessionId)
            let ref = SessionRef(
                machineID: model.id, sessionId: sessionId, agent: session?.agent ?? "",
                workspaceTitle: session?.workspaceTitle ?? "")
            for (id, continuation) in chatSubscribers {
                if case .terminated = continuation.yield((ref, entries)) { chatSubscribers[id] = nil }
            }
        case .signedOut:
            Task { await self.reportUnauthorized() }
        }
    }

    private func revoke(_ model: MachineModel) async {
        await disconnect(model)
        model.state = .revoked
        model.pending = PendingSet()
        model.pendingActionable = false
        model.sessions = SessionSet()
    }

    private func suspend() async {
        suspended = true
        for model in machines {
            guard inBackground else { break }
            guard connections[model.id] != nil else { continue }
            if !model.state.isTerminal {
                model.pendingActionable = false
                if model.state == .online { model.state = .reconnecting }
            }
            await disconnect(model)
        }
        // The app came back while the sessions were closing.
        if !inBackground { resume() }
    }

    private func resume() {
        suspended = false
        for model in machines where !model.state.isTerminal && connections[model.id] == nil {
            connect(model)
        }
    }

    private func withLink<T: Sendable>(
        _ machineID: String, _ body: @Sendable (LinkClient) async throws -> T
    ) async throws -> T {
        guard let model = machines.first(where: { $0.id == machineID }) else { throw LinkCallError.unknownMachine }
        guard let connection = connections[machineID] else { throw LinkCallError.offline(machineName: model.name) }
        do {
            return try await connection.call(body)
        } catch LinkCallError.offline {
            throw LinkCallError.offline(machineName: model.name)
        }
    }

    private func reportUnauthorized() async {
        guard !unauthorizedReported else { return }
        unauthorizedReported = true
        await onUnauthorized()
    }

    private static func upsert(_ machine: PairedMachine, into list: inout [PairedMachine]) {
        if let index = list.firstIndex(where: { $0.machineID == machine.machineID }) {
            list[index] = machine
        } else {
            list.append(machine)
        }
    }
}

extension MachineHub {
    public enum AddError: Error, Equatable {
        /// No account is signed in (or the hub was stopped by a sign-out).
        case notSignedIn
    }
}
