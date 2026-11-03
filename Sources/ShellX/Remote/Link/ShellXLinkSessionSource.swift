import Bonsplit
import CmuxAgentChat
import CmuxMobileHost
import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// ShellX: ShellX Link's list of agent sessions (`agent.sessions`), read from the agent chat session registry
/// of ``AgentChatTranscriptService``.
///
/// * The list is every Claude Code agent session (v1 phones answer Claude Code only) that is not ended,
///   plus the ``maxEndedSessions`` most recently active ended ones whose transcript is still readable.
/// * Closing a terminal (its tab or workspace) ends its agent: Ghostty hangs up, then terminates and kills its
///   process groups. Once ended, a closed terminal's session is not listed, not even as ended. A session still
///   running after its terminal closed stays listed, so the phone never loses sight of a live agent. A session
///   that names no terminal (an agent run outside ShellX) is listed like any other. A terminal in a Dock is
///   open like one in a workspace, and while the app launches (no window yet, restore unfinished) no terminal
///   is taken for closed.
/// * `revision` counts changes of that list: every published difference raises it by exactly 1
///   (PROTOCOL.md 4), and ``sessions()`` publishes any difference it finds before answering, so a list at
///   revision r includes every change up to r.
/// * Changes come from the service's frames (`stateChanged`, `descriptorChanged`, `sessionRemoved`) and from
///   the change signal (a terminal closing). Both are watched only while someone subscribes to
///   ``sessionChanges()``; the frame observer also keeps the service publishing session frames with no mobile
///   client subscribed.
///
/// All state is main-actor isolated, like the service. `onTermination` only schedules the removal on the
/// main actor, so it never waits for anything `yield` holds.
@MainActor
final class ShellXLinkSessionSource: AgentSessionSource {
    /// The workspace a session belongs to, or nil when no live workspace owns it.
    typealias WorkspaceLookup = @MainActor (ChatSessionDescriptor) -> (id: String, title: String)?
    /// The surface ids of the terminals open on the Mac (in a workspace or a Dock), or nil when that is not
    /// known yet. Read at most once per refresh.
    typealias OpenTerminals = @MainActor () -> Set<UUID>?
    typealias ChangeSignal = ShellXLinkWorkspaceSource.ChangeSignal
    typealias Change = (revision: Int, upserted: [AgentSession], removed: [String])

    /// Ended sessions listed at most: the hook store keeps up to 512 sessions for a week, more than an
    /// `agent.sessions` frame holds.
    static let maxEndedSessions = 20

    private let serviceProvider: @MainActor () -> AgentChatTranscriptService?
    private let workspaceLookup: WorkspaceLookup
    private let openTerminals: OpenTerminals
    private let changeSignal: ChangeSignal
    private var subscribers: [UUID: AsyncStream<Change>.Continuation] = [:]
    /// Streams that ended before their subscription ran; never subscribed afterwards.
    private var endedEarly: Set<UUID> = []
    private var observation: (service: AgentChatTranscriptService, token: UUID)?
    private var stopSignal: (@MainActor () -> Void)?
    /// The list as last published, most recently active first.
    private var published: [AgentSession] = []
    private var revision = 0

    /// - Parameters:
    ///   - service: The app's transcript service; nil until the app wires it.
    ///   - workspaceLookup: Finds a session's workspace; the default asks the open windows for the workspace
    ///     that owns the session's terminal. Tests pass a fixed answer.
    ///   - openTerminals: The terminals still open; the default asks the open windows and Docks.
    ///   - changeSignal: Tells the source when to look again for closed terminals (an ended session's tab
    ///     closing); the default watches the windows, their workspaces and panels.
    init(
        service: @escaping @MainActor () -> AgentChatTranscriptService? = { TerminalController.shared.agentChatTranscriptService },
        workspaceLookup: @escaping WorkspaceLookup = ShellXLinkSessionSource.liveWorkspace,
        openTerminals: @escaping OpenTerminals = ShellXLinkSessionSource.liveOpenTerminals,
        changeSignal: @escaping ChangeSignal = ShellXLinkWorkspaceSource.liveChangeSignal
    ) {
        self.serviceProvider = service
        self.workspaceLookup = workspaceLookup
        self.openTerminals = openTerminals
        self.changeSignal = changeSignal
    }

    /// Live subscriptions (tests).
    var subscriberCount: Int { subscribers.count }

    // MARK: - AgentSessionSource

    func sessions() async -> (revision: Int, sessions: [AgentSession]) {
        refresh()
        return (revision, published)
    }

    nonisolated func sessionChanges() -> AsyncStream<(revision: Int, upserted: [AgentSession], removed: [String])> {
        let (stream, continuation) = AsyncStream<Change>.makeStream(bufferingPolicy: .unbounded)
        let id = UUID()
        // Synchronous from cancellation, `finish()` or release: only schedule the removal.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.unsubscribe(id) }
        }
        // `LinkHost` subscribes before `welcome` and asks for the list after it; that call's main-actor hop
        // runs after this one, so the phone's starting point precedes every change it is sent.
        Task { @MainActor in self.subscribe(id, continuation) }
        return stream
    }

    // MARK: - Subscriptions

    private func subscribe(_ id: UUID, _ continuation: AsyncStream<Change>.Continuation) {
        guard endedEarly.remove(id) == nil else { return }
        if subscribers.isEmpty {
            refresh()   // catch up while nobody listened, before this subscriber's first change
            startObserving()
            stopSignal = changeSignal { [weak self] in self?.refresh() }
        }
        subscribers[id] = continuation
    }

    private func unsubscribe(_ id: UUID) {
        guard subscribers.removeValue(forKey: id) != nil else {
            endedEarly.insert(id)
            return
        }
        guard subscribers.isEmpty else { return }
        if let observation {
            observation.service.removeFrameObserver(observation.token)
            self.observation = nil
        }
        stopSignal?()
        stopSignal = nil
    }

    private func startObserving() {
        guard observation == nil, let service = serviceProvider() else { return }
        let token = service.addFrameObserver { [weak self] frame in self?.receive(frame) }
        observation = (service, token)
    }

    private func receive(_ frame: ChatSessionEventFrame) {
        switch frame.event {
        case .stateChanged, .descriptorChanged, .sessionRemoved:
            refresh()
        case .appended, .updated, .terminalBlocks, .streamingProse, .reset, .unknown:
            break
        }
    }

    /// Compares the registry's list with the published one and publishes the difference, if any.
    private func refresh() {
        guard let service = serviceProvider() else { return }
        if !subscribers.isEmpty { startObserving() }
        let current = Self.listedRecords(service, openTerminals: openTerminals).map(makeSession)
        let known = Dictionary(published.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        let upserted = current.filter { known[$0.sessionId] != $0 }
        let currentIDs = Set(current.map(\.sessionId))
        let removed = published.map(\.sessionId).filter { !currentIDs.contains($0) }
        published = current
        guard !upserted.isEmpty || !removed.isEmpty else { return }
        revision += 1
        for continuation in subscribers.values {
            continuation.yield((revision: revision, upserted: upserted, removed: removed))
        }
    }

    // MARK: - Mapping

    /// The listed records, most recently active first: Claude Code agent sessions that are not ended, and the
    /// most recent listable ended ones, leaving out the ended ones whose terminal was closed.
    ///
    /// `openTerminals` is read once, when the first ended session naming a terminal comes up.
    static func listedRecords(
        _ service: AgentChatTranscriptService, openTerminals: OpenTerminals
    ) -> [AgentChatSessionRecord] {
        var listed: [AgentChatSessionRecord] = []
        var endedCount = 0
        var open: Set<UUID>??
        for record in service.sessionRecords(workspaceID: nil)
        where record.agentKind == .claude && record.descriptor.kind == .agent {
            // Before the ended count, so a closed tab's sessions do not take the slots of listable ones.
            if record.state == .ended,
               let terminal = record.descriptor.terminalID.flatMap(UUID.init(uuidString:)) {
                if open == nil { open = .some(openTerminals()) }
                if let known = open ?? nil, !known.contains(terminal) { continue }
            }
            guard record.state == .ended else {
                listed.append(record)
                continue
            }
            guard endedCount < maxEndedSessions, service.shouldListEndedSession(record) else { continue }
            endedCount += 1
            listed.append(record)
        }
        return listed
    }

    private func makeSession(_ record: AgentChatSessionRecord) -> AgentSession {
        let descriptor = record.descriptor
        let workspace = workspaceLookup(descriptor)
        let fallbackTitle = record.workingDirectory.map { ($0 as NSString).lastPathComponent } ?? ""
        let (state, since): (AgentState, Date?) = switch record.state {
        case .idle: (.idle, nil)
        case .working(let since): (.working, since)
        case .needsInput(let since): (.needsInput, since)
        case .ended: (.ended, record.endedAt)
        }
        return AgentSession(
            sessionId: record.sessionID,
            agent: ChatAgentKind.claude.sourceName,
            workspaceId: workspace?.id ?? record.workspaceID ?? "",
            workspaceTitle: workspace?.title ?? fallbackTitle,
            title: descriptor.title,
            state: state,
            stateSinceMs: since.flatMap(Self.unixMs),
            lastActivityMs: Self.unixMs(record.lastActivityAt)
        )
    }

    /// Unix milliseconds, or nil for a date before 1970 (a record seeded without an activity time).
    static func unixMs(_ date: Date) -> Int64? {
        let ms = (date.timeIntervalSince1970 * 1000).rounded()
        return ms > 0 ? Int64(ms) : nil
    }

    /// The open workspace that owns the session's terminal (its recorded workspace id goes stale across
    /// relaunches; the surface id does not), else the recorded workspace when it is still open. Titled like
    /// ``ShellXLinkFeedSource/liveWorkspace(_:)``.
    static func liveWorkspace(_ descriptor: ChatSessionDescriptor) -> (id: String, title: String)? {
        guard let app = AppDelegate.shared else { return nil }
        let recorded = descriptor.workspaceID.flatMap(UUID.init(uuidString:))
        if let surface = descriptor.terminalID.flatMap(UUID.init(uuidString:)),
           let owner = app.workspaceContainingPanel(panelId: surface, preferredWorkspaceId: recorded) {
            return (owner.workspace.id.uuidString, owner.workspace.title)
        }
        guard let recorded, let workspace = app.tabManagerFor(tabId: recorded)?.workspacesById[recorded] else {
            return nil
        }
        return (recorded.uuidString, workspace.title)
    }

    /// The terminals open in the app's main windows (including one being recovered) and its live Docks, in
    /// one pass. Nil, so nothing is hidden on a guess, with no app to ask or while the app launches.
    static func liveOpenTerminals() -> Set<UUID>? {
        guard let app = AppDelegate.shared else { return nil }
        var seen: Set<ObjectIdentifier> = []
        let managers = app.mainWindowContexts.values.map(\.tabManager)
            + app.recoverableMainWindowRoutes().compactMap(\.tabManager)
        let windows = managers.filter { seen.insert(ObjectIdentifier($0)).inserted }.map(\.tabs)
        return openTerminals(
            restoreFinished: ShellXSessionRestoreSignal.completed.value,
            workspacesByWindow: windows,
            docks: DockSplitStore.liveStores
        )
    }

    /// The terminals open in these windows' workspaces and in these Docks, or nil when that is not known:
    /// before the launch's session restore has finished, or while no main window is registered, a terminal
    /// still being restored would read as closed.
    static func openTerminals(
        restoreFinished: Bool, workspacesByWindow: [[Workspace]], docks: [DockSplitStore]
    ) -> Set<UUID>? {
        guard restoreFinished, !workspacesByWindow.isEmpty else { return nil }
        return openTerminalSurfaceIDs(workspaces: workspacesByWindow.flatMap { $0 }, docks: docks)
    }

    /// Every id a hook may name one of these terminals by (`CMUX_SURFACE_ID` is the terminal panel's id), the
    /// ids `Workspace.surfaceOwnershipTarget(for:)` and `DockSplitStore.containsPanel(_:)` resolve: panel ids,
    /// split-tree surface ids, remote tmux pane surfaces and Dock terminal surfaces. A few non-terminal ids
    /// may be among them; that only keeps a session listed.
    static func openTerminalSurfaceIDs(workspaces: [Workspace], docks: [DockSplitStore]) -> Set<UUID> {
        var open: Set<UUID> = []
        for workspace in workspaces {
            open.formUnion(workspace.panels.keys)
            open.formUnion(workspace.surfaceIdToPanelId.keys.map(\.uuid))
            if let mirror = workspace.remoteTmuxSessionMirror {
                open.formUnion(mirror.controlPaneLocations().map(\.pane.panel.id))
            }
            for mirror in workspace.remoteTmuxWindowMirrors.values {
                open.formUnion(mirror.surfaceIDsInLayoutOrder)
            }
        }
        for dock in docks {
            open.formUnion(dock.panels.keys)
            open.formUnion(dock.surfaceIdToPanelId.keys.map(\.uuid))
            for panel in dock.panels.values {
                if let terminal = panel as? TerminalPanel { open.insert(terminal.surface.id) }
            }
        }
        return open
    }
}
