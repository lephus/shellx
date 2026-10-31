import Foundation
import Observation
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkSession
import os

/// Every paired Mac and its Link, for the signed-in account: one `MachineConnection` per Mac, the
/// merged pending items and live sessions, and the calls that act on them.
///
/// The hub is the only writer of the vault's Mac list: `start()` reads it, `add(_:)` and
/// `unpair(machineID:)` write it.
@MainActor @Observable
public final class MachineHub {
    /// How long sessions stay open after the app went to the background.
    public static let backgroundGrace: Duration = .seconds(25)
    static let defaultMachineKey = "shellx.defaultMachineID"
    /// How many items `leftWhileSynced(_:)` remembers; the oldest go first.
    static let handledMemory = 256

    public private(set) var machines: [MachineModel] = []
    /// True once `start()` read the vault, so an empty `machines` means "no Mac paired yet".
    public private(set) var isLoaded = false
    private var storedDefaultMachineID: String?
    /// Items that left a Mac's list while the Mac was live and synced, newest last
    /// (`leftWhileSynced(_:)`).
    private var handledKeys: [PendingKey] = []
    /// Per Mac, the sessions that finished a turn and that the user has not looked at since, each with
    /// when the phone saw it finish (`finishedSessionIds(machineID:)`). The Mac sends no finish time for
    /// an idle session, so this is the phone's clock. In memory only: a launch starts with none.
    public private(set) var finishTimes: [String: [String: Date]] = [:]

    @ObservationIgnored private let vault: AccountVault
    @ObservationIgnored private let relay: any RelayAccountCalling
    @ObservationIgnored private let connector: any MachineLinkConnecting
    @ObservationIgnored private let latency: LatencyLog
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let onUnauthorized: @MainActor () async -> Void
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let log = Logger(subsystem: "com.shellx.app", category: "link")

    /// The vault's Mac list as last read or written.
    @ObservationIgnored private var records: [PairedMachine] = []
    @ObservationIgnored private var connections: [String: MachineConnection] = [:]
    @ObservationIgnored private var readers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var chatSubscribers: [UUID: AsyncStream<ChatUpdate>.Continuation] = [:]
    @ObservationIgnored private var sessionSubscribers:
        [UUID: AsyncStream<(machineID: String, sessions: [AgentSession])>.Continuation] = [:]
    @ObservationIgnored private var stateSubscribers:
        [UUID: AsyncStream<(machineID: String, state: MachineLinkState)>.Continuation] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var stopped = false
    /// The app is in the background (until `appDidBecomeActive()`).
    @ObservationIgnored private var inBackground = false
    /// The sessions were closed because the app stayed in the background past the grace.
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var grace: Task<Bool, Never>?
    @ObservationIgnored private var unauthorizedReported = false
    /// Transcript resets (`chat.reset`) per session since the hub started (`transcriptResets(of:)`).
    @ObservationIgnored private var resetCounts: [SessionRef: Int] = [:]
    /// Tells which sessions finished a turn, from every session list a Mac sends (`finishTimes`).
    @ObservationIgnored private var finishDetector = SessionFinishDetector()

    public init(
        vault: AccountVault, relay: any RelayAccountCalling, connector: any MachineLinkConnecting,
        latency: LatencyLog, defaults: UserDefaults, sleep: @escaping @Sendable (Duration) async throws -> Void,
        onUnauthorized: @escaping @MainActor () async -> Void, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.vault = vault
        self.relay = relay
        self.connector = connector
        self.latency = latency
        self.defaults = defaults
        self.sleep = sleep
        self.onUnauthorized = onUnauthorized
        self.now = now
        storedDefaultMachineID = defaults.string(forKey: Self.defaultMachineKey)
    }

    // MARK: - What the UI reads

    /// The default Mac has answered with its workspace list (`MachineModel.workspacesSupported`): what
    /// `LatencyMetric.launchToWorkspaceList` waits for.
    public var defaultMachineListedWorkspaces: Bool {
        guard let id = defaultMachineID else { return false }
        return machines.first { $0.id == id }?.workspacesSupported ?? false
    }

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

    /// True when the item left its Mac's list while the Mac was live and synced: the Mac's own list
    /// said it is no longer pending, so it was decided (on the Mac, another phone, or by the agent).
    /// Items dropped because the link went down, or the Mac removed this iPhone, are not.
    public func leftWhileSynced(_ key: PendingKey) -> Bool {
        handledKeys.contains(key)
    }

    /// How many times the session's transcript was reset (`chat.reset`) since the hub started,
    /// counted as each reset arrives, before any subscriber sees it. A screen that stopped following
    /// the chat compares it when it follows again: a reset it missed voids its copy.
    public func transcriptResets(of ref: SessionRef) -> Int {
        resetCounts[ref, default: 0]
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

    /// Every session, in every state, of the Macs that are online, connecting or reconnecting: a Mac
    /// that is back keeps its sessions, with `online` false until it answers. A Mac that is offline
    /// contributes none. Most recent activity first, as in `liveSessions`.
    public var reachableSessions: [MachineSession] {
        machines.filter { [.online, .connecting, .reconnecting].contains($0.state) }.flatMap { model in
            model.sessions.sessions.map {
                MachineSession(machineID: model.id, machineName: model.name, online: model.state == .online, session: $0)
            }
        }
        .sorted { a, b in
            let (lhs, rhs) = (a.session.lastActivityMs ?? .min, b.session.lastActivityMs ?? .min)
            return lhs != rhs ? lhs > rhs : (a.machineID, a.session.sessionId) < (b.machineID, b.session.sessionId)
        }
    }

    // MARK: - Workspaces

    /// The Mac's workspaces as rows, in the Mac's order, each with the state worked out from the Mac's
    /// sessions, pending requests and `finishedSessionIds(machineID:)`. An offline Mac's rows are its
    /// last known ones. Empty for a Mac that lists no workspaces, and for an unknown one.
    public func workspaceRows(machineID: String) -> [WorkspaceRow] {
        guard let model = machines.first(where: { $0.id == machineID }) else { return [] }
        let pending = model.pending.items.map {
            MachinePendingItem(machineID: model.id, machineName: model.name, item: $0, actionable: model.pendingActionable)
        }
        return WorkspaceRow.rows(
            workspaces: model.workspaces, sessions: model.sessions.sessions, pending: pending,
            finished: finishedSessionIds(machineID: machineID), machineID: machineID)
    }

    /// The Mac's sessions that have not ended and that no terminal of its workspaces names
    /// (`LinkTerminal.sessionId`): the ones with no terminal chip, among them sessions whose workspace
    /// is gone or was never named. Most recent activity first.
    public func otherSessions(machineID: String) -> [MachineSession] {
        guard let model = machines.first(where: { $0.id == machineID }) else { return [] }
        let named = Self.namedSessionIds(model)
        return model.sessions.sessions.filter { $0.state != .ended && !named.contains($0.sessionId) }.map {
            MachineSession(machineID: model.id, machineName: model.name, online: model.state == .online, session: $0)
        }
    }

    /// True when a terminal of the Mac's listed workspaces names the session (`LinkTerminal.sessionId`):
    /// the Mac finds the session's tab there, which `agent.close` needs. The sessions that have not ended
    /// and that this is false for are `otherSessions(machineID:)`. False for an unknown Mac.
    public func hasListedTerminal(_ ref: SessionRef) -> Bool {
        guard let model = machines.first(where: { $0.id == ref.machineID }) else { return false }
        return Self.namedSessionIds(model).contains(ref.sessionId)
    }

    /// The sessions a terminal of the Mac's listed workspaces names.
    private static func namedSessionIds(_ model: MachineModel) -> Set<String> {
        Set(model.workspaces.workspaces.flatMap(\.terminals).compactMap(\.sessionId))
    }

    /// The Mac's sessions that finished a turn (went from working or waiting to idle) and have not
    /// started again since, until `markSeen(_: WorkspaceRef)` clears their workspace or `markSeen(_: SessionRef)`
    /// clears the one session. `WorkspaceRow` shows them as
    /// `.done`. Only what this launch saw; nothing is saved.
    public func finishedSessionIds(machineID: String) -> Set<String> {
        Set((finishTimes[machineID] ?? [:]).keys)
    }

    /// The user looked at the workspace (its screen opened): its finished sessions stop counting as
    /// `.done`, until one of them finishes again.
    public func markSeen(_ ref: WorkspaceRef) {
        guard let model = machines.first(where: { $0.id == ref.machineID }), let finished = finishTimes[ref.machineID]
        else { return }
        let terminals = model.workspaces.workspace(ref.workspaceId)?.terminals ?? []
        let mine = WorkspaceRow.sessionIds(
            workspaceId: ref.workspaceId, terminals: terminals, among: model.sessions.sessions)
        let rest = finished.filter { !mine.contains($0.key) }
        if rest.count != finished.count { finishTimes[ref.machineID] = rest.isEmpty ? nil : rest }
    }

    /// The user opened one agent: that session stops counting as finished, until it finishes again.
    public func markSeen(_ ref: SessionRef) {
        guard var finished = finishTimes[ref.machineID], finished.removeValue(forKey: ref.sessionId) != nil else { return }
        finishTimes[ref.machineID] = finished.isEmpty ? nil : finished
    }

    /// True when the Mac listed the `workspace_control` feature when it was last online: the app offers
    /// to make, rename and close workspaces for it only then. False for a Mac never online yet.
    public func supportsWorkspaceControl(_ machineID: String) -> Bool {
        machines.first { $0.id == machineID }?.hostFeatures.contains(ShellXLink.workspaceControlFeature) ?? false
    }

    /// True when the Mac listed the `agent_close` feature when it was last online: the app offers to close
    /// an agent for it only then. False for a Mac never online yet, and for one from before the feature.
    public func supportsAgentClose(_ machineID: String) -> Bool {
        machines.first { $0.id == machineID }?.hostFeatures.contains(ShellXLink.agentCloseFeature) ?? false
    }

    /// True when the Mac listed the `terminal_close` feature when it was last online: the app offers to
    /// close a terminal tab for it only then. False for a Mac never online yet, and for one from before the
    /// feature.
    public func supportsTerminalClose(_ machineID: String) -> Bool {
        machines.first { $0.id == machineID }?.hostFeatures.contains(ShellXLink.terminalCloseFeature) ?? false
    }

    /// Asks the Mac (`machineID`), or every online Mac, for its workspace list again: a pull to refresh,
    /// or a command that found its workspace gone. The list is kept in sync by pushes, so this changes
    /// something only when one was missed. Returns when the answers are in.
    public func refreshWorkspaces(machineID: String? = nil) async {
        let live = machines.filter { $0.state == .online && (machineID == nil || $0.id == machineID) }
            .compactMap { connections[$0.id] }
        await withTaskGroup(of: Void.self) { group in
            for connection in live { group.addTask { await connection.refreshWorkspaces() } }
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
        isLoaded = true
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
        for continuation in stateSubscribers.values { continuation.finish() }
        chatSubscribers = [:]
        sessionSubscribers = [:]
        stateSubscribers = [:]
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
            // A sign-out may have stopped the hub while the old connection closed.
            guard !stopped else { return }
            model.replace(with: machine)
            forgetFinishes(of: model.id)
            connect(model)
        } else {
            let model = MachineModel(machine: machine)
            machines.append(model)
            connect(model)
        }
    }

    /// Removes this iPhone from a Mac: finds the Mac's grant with `machines(token:)`, deletes it on
    /// the relay, then forgets the Mac (vault, connection, list, default).
    ///
    /// A grant that is already gone (not listed, or 404) still forgets the Mac. Any other relay error
    /// (network, 5xx) throws and keeps the Mac as it was; a 401 also signs out. A `.revoked` Mac has
    /// no grant left, so it is forgotten even when the relay cannot be reached. An unknown
    /// `machineID` does nothing.
    public func unpair(machineID: String) async throws {
        guard let model = machines.first(where: { $0.id == machineID }) else { return }
        guard !stopped, let session = try await vault.session() else { throw AddError.notSignedIn }
        do {
            try await removeGrant(of: machineID, token: session.token)
        } catch {
            if LinkFailure(error) == .signedOut {
                await reportUnauthorized()
                throw error
            }
            // The Mac already let this iPhone go: nothing is left on the relay to remove.
            guard model.state == .revoked else { throw error }
            log.notice("unpair_revoked_relay_unreachable")
        }
        // A sign-out meanwhile wipes the vault: writing the list now would bring it back.
        guard !stopped else { throw AddError.notSignedIn }
        try await forget(machineID, owner: session.userID)
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
        // What each Mac was paired as when the request left: a Mac re-paired meanwhile (replaced in
        // place by `add`) or added meanwhile may not be in this list yet.
        let known = machines.map { (model: $0, machine: $0.machine) }
        let grants: [PairedMachineListing]
        do {
            grants = try await relay.machines(token: token)
        } catch {
            if LinkFailure(error) == .signedOut { await reportUnauthorized() }
            return
        }
        guard !stopped else { return }
        let byID = Dictionary(grants.map { ($0.machineID, $0) }, uniquingKeysWith: { first, _ in first })
        for (model, machine) in known where model.machine == machine && machines.contains(where: { $0 === model }) {
            guard !stopped else { return }
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
        guard !stopped, !suspended else { return }
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

    /// iOS ends the background time before the grace ran out, or granted none: closes every session
    /// now. Everything that matters happens before this returns (items not actionable, connections
    /// detached), so a return to the app reconnects every Mac from scratch even if the app is frozen
    /// before the sessions finish closing.
    public func backgroundTimeExpired() {
        guard !stopped, !suspended else { return }
        inBackground = true
        grace?.cancel()
        grace = nil
        let closing = detachAll()
        Task { for connection in closing { await connection.stop() } }
    }

    /// The network path changed (Wi-Fi to cellular, a new Wi-Fi, back online): a session, or an
    /// attempt still syncing, may ride a dead path without anyone knowing yet, so each connection
    /// replaces its client at once, and one without a client retries now. The connection decides
    /// from its own state; the model's copy may lag.
    public func networkChanged() {
        guard !stopped, !suspended else { return }
        for connection in connections.values {
            Task { await connection.forceReconnect() }
        }
    }

    // MARK: - Calls

    /// Sends one `agent.reply`. `DecisionCenter` calls it for a tap (and records `replyRoundTrip`
    /// from the tap, across its one resend).
    public func reply(_ key: PendingKey, decision: LinkDecision) async throws -> ReplyOutcome {
        try await withLink(key.machineID) {
            try await $0.reply(requestId: key.requestId, decision: decision)
        }
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

    /// True when the Mac listed the `attachments` feature when it was last online: the composer
    /// offers photos and files for its sessions only then. False for a Mac never online yet.
    public func acceptsAttachments(_ machineID: String) -> Bool {
        machines.first { $0.id == machineID }?.hostFeatures.contains(ShellXLink.attachmentsFeature) ?? false
    }

    /// Sends `text` with `attachments` (none: as `chatSend(_:text:)`). Each attachment is uploaded in
    /// turn, then one `chat.send` names them all, inside one call on the Mac's session: an upload id
    /// is valid only in the session that made it. The Link client holds its upload turn for the whole
    /// message (`LinkClient.chatSend(sessionId:text:uploading:progress:)`), so two messages sent at once
    /// go one after the other. Nothing is uploaded to a Mac whose session did not list the
    /// `attachments` feature.
    ///
    /// `progress` gets the bytes uploaded so far over the bytes of every attachment, after each
    /// chunk the Mac took (1 once the last one is up). It runs on the Link client's actor.
    ///
    /// Throws `LinkCallError` when nothing was sent, as `chatSend(_:text:)` does, and
    /// `AttachmentSendError` when the message surely did not reach the session: an upload failed,
    /// or the Mac refused an upload or the message (it then types nothing), or it does not take
    /// attachments. Any other error comes after the message left: it may have arrived.
    public func chatSend(
        _ ref: SessionRef, text: String, attachments: [OutgoingAttachment], progress: @Sendable (Double) -> Void
    ) async throws -> ChatSendOutcome {
        guard !attachments.isEmpty else { return try await chatSend(ref, text: text) }
        let total = attachments.reduce(0) { $0 + $1.data.count }
        do {
            return try await withLink(ref.machineID) { client in
                guard client.hostFeatures.contains(ShellXLink.attachmentsFeature) else {
                    throw AttachmentSendError.refused(code: "unsupported")
                }
                let uploads = attachments.map { ChatAttachment(kind: $0.kind, name: $0.name, data: $0.data) }
                do {
                    // One call: the client keeps its upload turn until the Mac answers the message, so another
                    // message to this Mac never makes the Mac drop one of these uploads.
                    return try await client.chatSend(sessionId: ref.sessionId, text: text, uploading: uploads) { sent in
                        progress(total > 0 ? Double(sent) / Double(total) : 1)
                    }
                } catch let error as MessageUploadError {
                    if case let LinkClientError.remote(code, _) = error.cause {
                        throw AttachmentSendError.refused(code: code)
                    }
                    // A timeout, the session closed, or this task cancelled: the message never left.
                    throw AttachmentSendError.uploadFailed
                } catch let LinkClientError.remote(code, _) {
                    // An error answer comes before anything is typed (an id expired or unknown, say).
                    throw AttachmentSendError.refused(code: code)
                }
            }
        } catch let error as AttachmentSendError {
            // Counts and sizes only: never a name or a byte of the attachments.
            let reason = String(describing: error)
            log.notice("attach_send_failed count=\(attachments.count) bytes=\(total) \(reason, privacy: .public)")
            throw error
        }
    }

    public func chatInterrupt(_ ref: SessionRef, hard: Bool) async throws -> ChatInterruptOutcome {
        try await withLink(ref.machineID) { try await $0.chatInterrupt(sessionId: ref.sessionId, hard: hard) }
    }

    /// Makes a workspace on the Mac, which chooses its directory. `.ok` carries the new workspace's id;
    /// it joins `workspaceRows(machineID:)` when the Mac's list change arrives.
    ///
    /// The three workspace commands are sent once, never again: when the link drops while waiting the
    /// result is `.unknown` (the Mac may have acted: look at the list), and nothing is sent to a Mac that
    /// is not `.online` (`.offline`) or that did not list `workspace_control` (`.failed`).
    public func createWorkspace(machineID: String) async -> WorkspaceCommandResult {
        await workspaceCommand(machineID, feature: ShellXLink.workspaceControlFeature) { client in
            let answer = try await client.createWorkspace()
            return WorkspaceCommandResult(outcome: answer.outcome, workspaceId: answer.workspaceId)
        }
    }

    /// Renames a workspace on its Mac. `title` is at most `ShellXLink.maxWorkspaceTitleBytes` UTF-8
    /// bytes (a longer one is `.failed`). See `createWorkspace(machineID:)`.
    public func renameWorkspace(_ ref: WorkspaceRef, title: String) async -> WorkspaceCommandResult {
        await workspaceCommand(ref.machineID, feature: ShellXLink.workspaceControlFeature) { client in
            WorkspaceCommandResult(outcome: try await client.renameWorkspace(workspaceId: ref.workspaceId, title: title))
        }
    }

    /// Closes a workspace and its terminals on its Mac, which keeps its own rules (`.refused` for its
    /// last workspace, for one). The row leaves when the Mac's list change arrives, not before. See
    /// `createWorkspace(machineID:)`.
    public func closeWorkspace(_ ref: WorkspaceRef) async -> WorkspaceCommandResult {
        await workspaceCommand(ref.machineID, feature: ShellXLink.workspaceControlFeature) { client in
            WorkspaceCommandResult(outcome: try await client.closeWorkspace(workspaceId: ref.workspaceId))
        }
    }

    /// Closes the terminal an agent runs in on its Mac, which keeps its own rules: it closes the whole
    /// workspace when that terminal is its last tab of any kind, `.refused` when remote control is blocked, the
    /// tab is pinned or the workspace is protected, `.notFound` for a session that has ended (its terminal runs the user's shell
    /// by then). `.ok` means the Mac closed it; the session turns `.ended` when the Mac's list change
    /// arrives, not before. A Mac that did not list `agent_close` (`supportsAgentClose(_:)`) gets nothing
    /// and the result is `.failed`. Sent once, like the workspace commands (see `createWorkspace(machineID:)`).
    public func closeAgent(_ ref: SessionRef) async -> WorkspaceCommandResult {
        await workspaceCommand(ref.machineID, feature: ShellXLink.agentCloseFeature) { client in
            WorkspaceCommandResult(outcome: try await client.closeAgent(sessionId: ref.sessionId))
        }
    }

    /// Closes one terminal tab of a workspace on its Mac, which keeps its own rules: it closes the whole
    /// workspace when that is the last tab (of any kind), `.refused` when remote control is blocked, the tab is
    /// pinned or the workspace is protected (or, for the last tab, when the Mac keeps a workspace open),
    /// `.notFound` for a terminal the Mac does not list in that workspace. Unlike `closeAgent(_:)` it does not
    /// look for a live agent: the user picked the tab. `.ok` means the Mac closed it; the tab leaves `workspaceRows(machineID:)` when
    /// the Mac's list change arrives, not before. A Mac that did not list `terminal_close`
    /// (`supportsTerminalClose(_:)`) gets nothing and the result is `.failed`. Sent once, like the workspace
    /// commands (see `createWorkspace(machineID:)`).
    public func closeTerminal(_ machineID: String, workspaceId: String, terminalId: String) async -> WorkspaceCommandResult {
        await workspaceCommand(machineID, feature: ShellXLink.terminalCloseFeature) { client in
            WorkspaceCommandResult(outcome: try await client.closeTerminal(workspaceId: workspaceId, terminalId: terminalId))
        }
    }

    /// Chat pushes from every Mac as they arrive, in order: entries, and transcript resets. Each call
    /// adds a subscriber, dropped when its reader stops. Nothing is kept for a later subscriber.
    public func chatUpdates() -> AsyncStream<ChatUpdate> {
        let (stream, continuation) = AsyncStream.makeStream(of: ChatUpdate.self)
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

    /// Each Mac's link state whenever its connection reports one (`.online` once a new session is
    /// synced, after every reconnect). Multicast like `chatUpdates()`.
    public func stateUpdates() -> AsyncStream<(machineID: String, state: MachineLinkState)> {
        let (stream, continuation) = AsyncStream.makeStream(of: (machineID: String, state: MachineLinkState).self)
        let id = UUID()
        stateSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stateSubscribers[id] = nil }
        }
        return stream
    }

    var chatSubscriberCount: Int { chatSubscribers.count }
    var connectionCount: Int { connections.count }
    var sessionSubscriberCount: Int { sessionSubscribers.count }

    // MARK: - Connections

    private func connect(_ model: MachineModel) {
        // A stopped hub (signed out, or 401) never starts a connection: nobody reads its events.
        guard !stopped else { return }
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
        case let .features(features):
            if model.hostFeatures != features { model.hostFeatures = features }
        case let .state(state):
            model.state = state
            for (id, continuation) in stateSubscribers {
                if case .terminated = continuation.yield((model.id, state)) { stateSubscribers[id] = nil }
            }
        case let .pending(set, actionable):
            if actionable { rememberHandled(leaving: model.pending, for: set, of: model) }
            model.pending = set
            model.pendingActionable = actionable
        case let .sessions(set, supported):
            model.sessions = set
            model.sessionsSupported = supported
            noteFinishes(in: set.sessions, of: model)
            for (id, continuation) in sessionSubscribers {
                if case .terminated = continuation.yield((model.id, set.sessions)) { sessionSubscribers[id] = nil }
            }
        case let .workspaces(set, supported):
            model.workspaces = set
            model.workspacesSupported = supported
        case let .chat(sessionId, entries):
            publishChat(sessionId, of: model) { .upsert($0, entries) }
        case let .chatReset(sessionId):
            resetCounts[SessionRef(machineID: model.id, sessionId: sessionId, agent: "", workspaceTitle: ""), default: 0] += 1
            publishChat(sessionId, of: model) { .reset($0) }
        case .signedOut:
            Task { await self.reportUnauthorized() }
        }
    }

    /// Takes the Mac's session list into the finish detector: the sessions it reports finished are
    /// `finishTimes` until they work again (or leave the list, or the user marks them seen).
    private func noteFinishes(in sessions: [AgentSession], of model: MachineModel) {
        let finished = finishDetector.observe(machineID: model.id, sessions: sessions)
        let idle = Set(sessions.filter { $0.state == .idle }.map(\.sessionId))
        let before = finishTimes[model.id] ?? [:]
        // A session already finished keeps its first time; a new finish gets the phone's clock now.
        var kept = before.filter { idle.contains($0.key) }
        let seenAt = now()
        for session in finished where kept[session.sessionId] == nil { kept[session.sessionId] = seenAt }
        if kept != before { finishTimes[model.id] = kept.isEmpty ? nil : kept }
    }

    /// Forgets what the finish detector knew of the Mac: its link is new, or gone.
    private func forgetFinishes(of machineID: String) {
        finishDetector.retain(machineIDs: Set(machines.map(\.id)).subtracting([machineID]))
        finishTimes[machineID] = nil
    }

    /// Records the items that leave `old` for `new`, a list backed by a live, synced session.
    private func rememberHandled(leaving old: PendingSet, for new: PendingSet, of model: MachineModel) {
        let kept = Set(new.items.map(\.requestId))
        let left = old.items.filter { !kept.contains($0.requestId) }
        guard !left.isEmpty else { return }
        handledKeys.append(contentsOf: left.map { PendingKey(machineID: model.id, requestId: $0.requestId) })
        if handledKeys.count > Self.handledMemory { handledKeys.removeFirst(handledKeys.count - Self.handledMemory) }
    }

    /// Hands a chat push to every subscriber, with the session's labels as the Mac lists it.
    private func publishChat(_ sessionId: String, of model: MachineModel, _ update: (SessionRef) -> ChatUpdate) {
        guard !chatSubscribers.isEmpty else { return }
        let session = model.sessions.session(sessionId)
        let ref = SessionRef(
            machineID: model.id, sessionId: sessionId, agent: session?.agent ?? "",
            workspaceTitle: session?.workspaceTitle ?? "")
        let value = update(ref)
        for (id, continuation) in chatSubscribers {
            if case .terminated = continuation.yield(value) { chatSubscribers[id] = nil }
        }
    }

    /// Deletes the relay's grant for `machineID`, if it still has one.
    private func removeGrant(of machineID: String, token: String) async throws {
        let grants = try await relay.machines(token: token)
        guard let grant = grants.first(where: { $0.machineID == machineID }) else { return }
        do {
            try await relay.unpair(grantID: grant.grantID, token: token)
        } catch RelayAPIError.http(status: 404, code: _) {
            // Removed meanwhile (on the Mac, or by another unpair).
        }
    }

    /// Takes the Mac out of the vault, then out of the hub. A failed vault write keeps everything.
    private func forget(_ machineID: String, owner: String) async throws {
        let old = records.first { $0.machineID == machineID }
        records.removeAll { $0.machineID == machineID }
        do {
            try await vault.setMachines(records, owner: owner)
        } catch {
            if let old { Self.upsert(old, into: &records) }
            throw error
        }
        // Re-pairing the same Mac later should not make it the default again by surprise.
        if storedDefaultMachineID == machineID { defaultMachineID = nil }
        guard let model = machines.first(where: { $0.id == machineID }) else { return }
        machines.removeAll { $0 === model }
        forgetFinishes(of: machineID)
        await disconnect(model)
    }

    private func revoke(_ model: MachineModel) async {
        await disconnect(model)
        model.state = .revoked
        model.pending = PendingSet()
        model.pendingActionable = false
        model.sessions = SessionSet()
        model.workspaces = WorkspaceSet()
        forgetFinishes(of: model.id)
    }

    private func suspend() async {
        for connection in detachAll() { await connection.stop() }
    }

    /// Marks every Mac as not live and takes every connection out of the hub, without waiting, so
    /// nothing can interleave halfway. Returns the connections for the caller to stop.
    private func detachAll() -> [MachineConnection] {
        suspended = true
        for model in machines where !model.state.isTerminal {
            model.pendingActionable = false
            if model.state == .online { model.state = .reconnecting }
        }
        for reader in readers.values { reader.cancel() }
        readers = [:]
        let detached = Array(connections.values)
        connections = [:]
        return detached
    }

    private func resume() {
        guard !stopped else { return }
        suspended = false
        for model in machines where !model.state.isTerminal && connections[model.id] == nil {
            connect(model)
        }
    }

    private func withLink<T: Sendable>(
        _ machineID: String, _ body: @Sendable (LinkClient) async throws -> T
    ) async throws -> T {
        guard let model = machines.first(where: { $0.id == machineID }) else { throw LinkCallError.unknownMachine }
        // It will not come back by itself, so it is not called offline.
        guard !model.state.needsPairing else { throw LinkCallError.needsPairing(machineName: model.name) }
        guard let connection = connections[machineID] else { throw LinkCallError.offline(machineName: model.name) }
        do {
            return try await connection.call(body)
        } catch LinkCallError.offline {
            throw LinkCallError.offline(machineName: model.name)
        }
    }

    /// Runs one command that needs the Mac's `feature` on its live session, and says how it went. It is
    /// never sent twice: after a timeout or a lost link the Mac may or may not have acted (PROTOCOL.md
    /// section 7).
    private func workspaceCommand(
        _ machineID: String, feature: String, _ body: @Sendable (LinkClient) async throws -> WorkspaceCommandResult
    ) async -> WorkspaceCommandResult {
        guard let model = machines.first(where: { $0.id == machineID }), model.state == .online else { return .offline }
        guard model.hostFeatures.contains(feature) else { return .failed }
        do {
            return try await withLink(machineID, body)
        } catch LinkCallError.offline, LinkCallError.needsPairing, LinkCallError.unknownMachine {
            // Nothing was sent.
            return .offline
        } catch LinkClientError.remote {
            // The Mac answered with an error (`unsupported`, `bad_request`): it did not act.
            return .failed
        } catch {
            // The request timed out, the session closed, or this task was cancelled while waiting.
            return .unknown
        }
    }

    /// The relay refused the account token (401): tells the app once, which signs out to the
    /// "session expired" sign-in. Also used by `PairingModel` for a 401 while pairing.
    func reportUnauthorized() async {
        // After a stop (a sign-out), a late 401 answers a request made with the dropped token.
        guard !unauthorizedReported, !stopped else { return }
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

extension MachineHub: DecisionSending {}

extension MachineHub {
    public enum AddError: Error, Equatable {
        /// No account is signed in (or the hub was stopped by a sign-out).
        case notSignedIn
    }
}
