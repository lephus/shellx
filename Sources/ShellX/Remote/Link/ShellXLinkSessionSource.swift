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
/// * `revision` counts changes of that list: every published difference raises it by exactly 1
///   (PROTOCOL.md 4), and ``sessions()`` publishes any difference it finds before answering, so a list at
///   revision r includes every change up to r.
/// * Changes come from the service's frames (`stateChanged`, `descriptorChanged`, `sessionRemoved`). The
///   frame observer is registered only while someone subscribes to ``sessionChanges()``; it also keeps the
///   service publishing session frames with no mobile client subscribed.
///
/// All state is main-actor isolated, like the service. `onTermination` only schedules the removal on the
/// main actor, so it never waits for anything `yield` holds.
@MainActor
final class ShellXLinkSessionSource: AgentSessionSource {
    /// The workspace a session belongs to, or nil when no live workspace owns it.
    typealias WorkspaceLookup = @MainActor (ChatSessionDescriptor) -> (id: String, title: String)?
    /// Whether the terminal with this surface id is open in a window.
    typealias TerminalIsOpen = @MainActor (UUID) -> Bool
    typealias ChangeSignal = ShellXLinkWorkspaceSource.ChangeSignal
    typealias Change = (revision: Int, upserted: [AgentSession], removed: [String])

    /// Ended sessions listed at most: the hook store keeps up to 512 sessions for a week, more than an
    /// `agent.sessions` frame holds.
    static let maxEndedSessions = 20

    private let serviceProvider: @MainActor () -> AgentChatTranscriptService?
    private let workspaceLookup: WorkspaceLookup
    private let terminalIsOpen: TerminalIsOpen
    private let changeSignal: ChangeSignal
    private var subscribers: [UUID: AsyncStream<Change>.Continuation] = [:]
    /// Streams that ended before their subscription ran; never subscribed afterwards.
    private var endedEarly: Set<UUID> = []
    private var observation: (service: AgentChatTranscriptService, token: UUID)?
    /// The list as last published, most recently active first.
    private var published: [AgentSession] = []
    private var revision = 0

    /// - Parameters:
    ///   - service: The app's transcript service; nil until the app wires it.
    ///   - workspaceLookup: Finds a session's workspace; the default asks the open windows for the workspace
    ///     that owns the session's terminal. Tests pass a fixed answer.
    ///   - terminalIsOpen: Whether a session's terminal is still open; the default asks the open windows.
    ///   - changeSignal: Tells the source when to look again for closed terminals; the default watches the
    ///     windows, their workspaces and panels.
    init(
        service: @escaping @MainActor () -> AgentChatTranscriptService? = { TerminalController.shared.agentChatTranscriptService },
        workspaceLookup: @escaping WorkspaceLookup = ShellXLinkSessionSource.liveWorkspace,
        terminalIsOpen: @escaping TerminalIsOpen = ShellXLinkSessionSource.liveTerminalIsOpen,
        changeSignal: @escaping ChangeSignal = ShellXLinkWorkspaceSource.liveChangeSignal
    ) {
        self.serviceProvider = service
        self.workspaceLookup = workspaceLookup
        self.terminalIsOpen = terminalIsOpen
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
        }
        subscribers[id] = continuation
    }

    private func unsubscribe(_ id: UUID) {
        guard subscribers.removeValue(forKey: id) != nil else {
            endedEarly.insert(id)
            return
        }
        guard subscribers.isEmpty, let observation else { return }
        observation.service.removeFrameObserver(observation.token)
        self.observation = nil
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
        let current = Self.listedRecords(service).map(makeSession)
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
    /// most recent listable ended ones.
    static func listedRecords(_ service: AgentChatTranscriptService) -> [AgentChatSessionRecord] {
        var listed: [AgentChatSessionRecord] = []
        var endedCount = 0
        for record in service.sessionRecords(workspaceID: nil)
        where record.agentKind == .claude && record.descriptor.kind == .agent {
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

    /// Whether a window holds the terminal. True with no app to ask, so nothing is hidden on a guess.
    static func liveTerminalIsOpen(_ terminal: UUID) -> Bool {
        guard let app = AppDelegate.shared else { return true }
        return app.workspaceContainingPanel(panelId: terminal) != nil
    }
}
