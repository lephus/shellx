import CmuxAgentChat
import CmuxMobileHost
import CmuxSidebar
import Combine
import Foundation
import os
import ShellXLinkCore
import ShellXLinkSession

/// ShellX: ShellX Link's list of this Mac's workspaces (`workspace.list`), the phone's control of them
/// (`workspace.create`, `workspace.rename`, `workspace.close`), and closing an agent's tab in them (`agent.close`),
/// PROTOCOL.md sections 4 ("Workspace") and 10.
///
/// * The list is every local workspace of every main window, in sidebar order: window order, then the order
///   within the window, numbered from 0 without a gap. SSH, remote tmux and cloud workspaces are not listed
///   (``Workspace/canHostLocalTerminal``), and neither are panels that are not terminals.
/// * `revision` counts changes of that list: every published difference raises it by exactly 1, and
///   ``workspaces()`` publishes any difference it finds before answering, so a list at revision r includes every
///   change up to r. Revision 0 is the first list built.
/// * Changes come from the change signal, which runs only while someone subscribes to ``workspaceChanges()``.
/// * Control calls go through cmux's mobile paths, which never select the new workspace or bring a window
///   forward. They act only on a workspace the list holds, and answer `refused` while a managed policy blocks
///   remote control, read on every call.
/// * `agent.close` closes only the terminal of a live agent (``ShellXLinkChatSource/isLiveAgent(_:)``), and only
///   while the list shows that terminal, in the workspace the list shows it in (a tab dragged elsewhere closes
///   there): never an SSH or remote one, and never the shell a tab runs once its agent has exited.
///
/// Titles, tab titles and directories are never logged. All state is main-actor isolated, like the windows it
/// reads; `onTermination` only schedules the removal on the main actor, so it never waits for anything `yield`
/// holds.
@MainActor
final class ShellXLinkWorkspaceSource: WorkspaceSource, WorkspaceControl, AgentControl {
    typealias Snapshot = @MainActor () -> [LinkWorkspace]
    /// Starts watching what the list shows and calls `onChange` after a change; returns the function that stops.
    typealias ChangeSignal = @MainActor (_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void
    typealias Change = (revision: Int, upserted: [LinkWorkspace], removed: [String])
    typealias V2CallResult = TerminalController.V2CallResult

    /// What the control calls do on the Mac. The live one uses cmux's mobile workspace paths.
    struct Control: Sendable {
        var create: @MainActor @Sendable () async -> V2CallResult
        var rename: @MainActor @Sendable (_ workspaceId: String, _ title: String) -> V2CallResult
        var close: @MainActor @Sendable (_ workspaceId: String) -> V2CallResult
        /// The terminal of a live agent session (``ShellXLinkChatSource/isLiveAgent(_:)``); nil for any other
        /// session, or a live one the Mac has not bound to a terminal.
        var agentSurface: @MainActor @Sendable (_ sessionId: String) -> UUID?
        /// Closes that terminal, or its workspace when it is the last one.
        var closeSurface: @MainActor @Sendable (_ workspaceId: UUID, _ surfaceId: UUID) -> V2CallResult
        /// Whether a configuration profile blocks remote control now.
        var isBlocked: @MainActor @Sendable () -> Bool

        static let live = Control(
            // Forces `focus` off and inherits the selected workspace's directory, like the add button.
            create: { await TerminalController.shared.v2MobileWorkspaceCreate(params: [:]) },
            rename: { workspaceId, title in
                TerminalController.shared.v2MobileWorkspaceAction(
                    params: ["action": "rename", "workspace_id": workspaceId, "title": title]
                )
            },
            // `force`: the phone confirmed already. The Mac still refuses its last or a protected workspace.
            close: { workspaceId in
                TerminalController.shared.v2MobileWorkspaceClose(params: ["workspace_id": workspaceId, "force": true])
            },
            agentSurface: { sessionId in
                ShellXLinkWorkspaceSource.liveAgentSurface(
                    TerminalController.shared.agentChatTranscriptService?.sessionRecord(sessionID: sessionId)
                )
            },
            // Without asking: the phone confirmed already.
            closeSurface: { workspaceId, surfaceId in
                TerminalController.shared.v2MobileAgentSurfaceClose(workspaceID: workspaceId, surfaceID: surfaceId)
            },
            isBlocked: { MobileRemoteControlPolicy.isDisabled }
        )
    }

    /// The most characters a title keeps (the wire allows 512 UTF-8 bytes, about 128 Vietnamese characters).
    static let maxTitleCharacters = 128

    /// The most changes a subscriber that does not keep up holds; older ones are dropped.
    nonisolated static let changeBufferLimit = 32

    nonisolated static let log = Logger(subsystem: "pro.shellx.desktop", category: "link-workspaces")

    private let snapshot: Snapshot
    private let control: Control
    private let changeSignal: ChangeSignal
    private var subscribers: [UUID: AsyncStream<Change>.Continuation] = [:]
    /// Streams that ended before their subscription ran; never subscribed afterwards.
    private var endedEarly: Set<UUID> = []
    private var stopSignal: (@MainActor () -> Void)?
    /// The list as last published; nil until the first one is built.
    private var published: [LinkWorkspace]?
    private var revision = 0

    /// - Parameters:
    ///   - snapshot: Builds the list; the default reads the main windows. Tests pass a fixed list.
    ///   - control: What the control calls do; tests pass a recorder.
    ///   - changeSignal: Tells the source when to look again; the default watches the windows and workspaces.
    init(
        snapshot: @escaping Snapshot = ShellXLinkWorkspaceSource.liveWorkspaces,
        control: Control = .live,
        changeSignal: @escaping ChangeSignal = ShellXLinkWorkspaceSource.liveChangeSignal
    ) {
        self.snapshot = snapshot
        self.control = control
        self.changeSignal = changeSignal
    }

    /// Live subscriptions (tests).
    var subscriberCount: Int { subscribers.count }

    // MARK: - WorkspaceSource

    func workspaces() async -> (revision: Int, workspaces: [LinkWorkspace]) {
        refresh()
        return (revision, published ?? [])
    }

    nonisolated func workspaceChanges() -> AsyncStream<(revision: Int, upserted: [LinkWorkspace], removed: [String])> {
        // A subscriber that falls behind loses the oldest changes, not memory: the phone sees the revision gap and
        // reads the list again (PROTOCOL.md section 4).
        let (stream, continuation) = AsyncStream<Change>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.changeBufferLimit)
        )
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

    // MARK: - WorkspaceControl

    func createWorkspace() async -> (outcome: WorkspaceControlOutcome, workspaceId: String?) {
        guard !control.isBlocked() else { return (.refused, nil) }
        let result = await control.create()
        let outcome = Self.outcome(of: result, action: "create")
        guard outcome == .ok else { return (outcome, nil) }
        refresh()
        return (.ok, Self.createdWorkspaceID(result))
    }

    func renameWorkspace(workspaceId: String, title: String) async -> WorkspaceControlOutcome {
        guard !control.isBlocked() else { return .refused }
        let clean = Self.sanitizedTitle(title)
        guard !clean.isEmpty else { return .failed }
        guard isListed(workspaceId) else { return .notFound }
        let outcome = Self.outcome(of: control.rename(workspaceId, clean), action: "rename")
        if outcome == .ok { refresh() }
        return outcome
    }

    func closeWorkspace(workspaceId: String) async -> WorkspaceControlOutcome {
        guard !control.isBlocked() else { return .refused }
        guard isListed(workspaceId) else { return .notFound }
        let outcome = Self.outcome(of: control.close(workspaceId), action: "close")
        if outcome == .ok { refresh() }
        return outcome
    }

    /// A phone names only a workspace the list holds (PROTOCOL.md 10): never an SSH or other remote one.
    private func isListed(_ workspaceId: String) -> Bool {
        refresh()
        return published?.contains { $0.workspaceId == workspaceId } ?? false
    }

    // MARK: - AgentControl

    /// Closes a live agent's terminal tab (PROTOCOL.md 10, "Agents"), or its workspace when it is the last tab and
    /// the Mac's Close Tab would close it. Only a tab the list shows, in the workspace the list shows it in: the Mac
    /// is asked nothing for any other session.
    func closeAgent(sessionId: String) async -> WorkspaceControlOutcome {
        guard !control.isBlocked() else { return .refused }
        guard let surface = control.agentSurface(sessionId),
              let workspace = listedWorkspace(holding: surface) else { return .notFound }
        let outcome = Self.outcome(of: control.closeSurface(workspace, surface), action: "close-agent")
        if outcome == .ok { refresh() }
        return outcome
    }

    /// The terminal `record` names when it is a live agent (``ShellXLinkChatSource/isLiveAgent(_:)``); nil for no
    /// record, any other record, or a terminal id that is not a UUID. Once the agent has exited its tab runs the
    /// user's shell, so this is what keeps a phone from closing it. The record's workspace is not used: it is where
    /// the shell started (`CMUX_WORKSPACE_ID`) and goes stale once the tab is dragged to another workspace.
    static func liveAgentSurface(_ record: AgentChatSessionRecord?) -> UUID? {
        guard let record, ShellXLinkChatSource.isLiveAgent(record) else { return nil }
        return record.surfaceID.flatMap(UUID.init(uuidString:))
    }

    /// The listed workspace whose terminals include `terminal`, wherever the tab has moved since its shell started,
    /// as `workspace.list` and `agent.sessions` show it; nil when no listed workspace has it (an SSH or other remote
    /// workspace, or a tab that is gone).
    private func listedWorkspace(holding terminal: UUID) -> UUID? {
        refresh()
        let terminalId = terminal.uuidString
        return published?
            .first { listed in listed.terminals.contains { $0.terminalId == terminalId } }
            .flatMap { UUID(uuidString: $0.workspaceId) }
    }

    /// The title a phone asked for, without control characters or line breaks, trimmed, and cut to
    /// ``maxTitleCharacters`` characters. Format characters such as the joiners of an emoji stay.
    static func sanitizedTitle(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: raw.unicodeScalars.filter {
            $0.properties.generalCategory != .control && !CharacterSet.newlines.contains($0)
        })
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxTitleCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The protocol's outcome for a cmux mobile call: `not_found` is not found; the Mac's own refusals
    /// (`protected`, `confirmation_required`, `invalid_state`, `denied`) are refused; anything else failed.
    static func outcome(of result: V2CallResult, action: String) -> WorkspaceControlOutcome {
        guard case let .err(code, _, _) = result else { return .ok }
        switch code {
        case "not_found":
            return .notFound
        case "protected", "confirmation_required", "invalid_state", "denied":
            return .refused
        default:
            // The code only: never the message, which may quote a title or a path.
            log.notice("workspace \(action, privacy: .public) failed: \(code, privacy: .public)")
            return .failed
        }
    }

    /// The new workspace's id in a mobile create answer (a workspace list naming it).
    private static func createdWorkspaceID(_ result: V2CallResult) -> String? {
        guard case let .ok(payload) = result, let payload = payload as? [String: Any] else { return nil }
        return payload["created_workspace_id"] as? String ?? payload["workspace_id"] as? String
    }

    // MARK: - Subscriptions

    private func subscribe(_ id: UUID, _ continuation: AsyncStream<Change>.Continuation) {
        guard endedEarly.remove(id) == nil else { return }
        if subscribers.isEmpty {
            refresh()   // catch up while nobody listened, before this subscriber's first change
            stopSignal = changeSignal { [weak self] in self?.refresh() }
        }
        subscribers[id] = continuation
    }

    private func unsubscribe(_ id: UUID) {
        guard subscribers.removeValue(forKey: id) != nil else {
            endedEarly.insert(id)
            return
        }
        guard subscribers.isEmpty, let stop = stopSignal else { return }
        stopSignal = nil
        stop()
    }

    /// Builds the list, compares it with the published one and publishes the difference, if any.
    private func refresh() {
        let current = snapshot()
        guard let previous = published else {
            published = current
            return
        }
        let known = Dictionary(previous.map { ($0.workspaceId, $0) }, uniquingKeysWith: { first, _ in first })
        let upserted = current.filter { known[$0.workspaceId] != $0 }
        let currentIDs = Set(current.map(\.workspaceId))
        let removed = previous.map(\.workspaceId).filter { !currentIDs.contains($0) }
        published = current
        guard !upserted.isEmpty || !removed.isEmpty else { return }
        revision += 1
        for continuation in subscribers.values {
            continuation.yield((revision: revision, upserted: upserted, removed: removed))
        }
    }

    // MARK: - The live list

    /// The local workspaces of every main window, from memory only (it answers inline in the Link host's
    /// read loop).
    static func liveWorkspaces() -> [LinkWorkspace] {
        rows(tabManagers: mainWindowTabManagers(), sessionIDs: liveSessionIDs())
    }

    /// Each main window's workspaces, in the window order cmux's mobile list uses.
    static func mainWindowTabManagers() -> [TabManager] {
        guard let app = AppDelegate.shared else { return [] }
        var seenWindows: Set<UUID> = []
        var seenManagers: Set<ObjectIdentifier> = []
        return app.listMainWindowSummaries().compactMap { summary in
            guard seenWindows.insert(summary.windowId).inserted,
                  let manager = app.tabManagerFor(windowId: summary.windowId),
                  seenManagers.insert(ObjectIdentifier(manager)).inserted else { return nil }
            return manager
        }
    }

    /// The list for these windows' workspaces, numbered across windows.
    ///
    /// - Parameter sessionIDs: The Claude Code session running in a terminal, by surface id.
    static func rows(tabManagers: [TabManager], sessionIDs: [UUID: String]) -> [LinkWorkspace] {
        let controller = TerminalController.shared
        var seen: Set<UUID> = []
        var rows: [LinkWorkspace] = []
        for manager in tabManagers {
            for workspace in manager.tabs where workspace.canHostLocalTerminal && seen.insert(workspace.id).inserted {
                rows.append(row(workspace, order: rows.count, controller: controller, sessionIDs: sessionIDs))
            }
        }
        return rows
    }

    private static func row(
        _ workspace: Workspace, order: Int, controller: TerminalController, sessionIDs: [UUID: String]
    ) -> LinkWorkspace {
        var seenPanels: Set<UUID> = []
        // Spatial order, as on screen.
        let panels = controller.mobileTerminalPanels(in: workspace).filter { seenPanels.insert($0.id).inserted }
        let terminals = panels.enumerated().map { index, panel in
            LinkTerminal(
                terminalId: panel.id.uuidString,
                title: workspace.panelTitle(panelId: panel.id) ?? panel.displayTitle,
                order: index,
                selected: workspace.isFocusedTerminalInputSurface(panel.id),
                sessionId: sessionIDs[panel.id]
            )
        }
        let branch = workspace.gitBranch?.branch
        let ports = workspace.listeningPorts
        return LinkWorkspace(
            workspaceId: workspace.id.uuidString,
            title: workspace.title,
            order: order,
            directory: displayDirectory(workspace.presentedCurrentDirectory),
            branch: branch?.isEmpty == false ? branch : nil,
            ports: ports.isEmpty ? nil : ports,
            terminals: terminals
        )
    }

    /// A directory as the sidebar shows it, with the home directory written `~`.
    static func displayDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private static func liveSessionIDs() -> [UUID: String] {
        guard let service = TerminalController.shared.agentChatTranscriptService else { return [:] }
        return sessionIDsByTerminal(service.sessionRecords(workspaceID: nil))
    }

    /// The Claude Code agent session that is not ended in each terminal, the most recently active one when a
    /// terminal has several: the sessions ``ShellXLinkSessionSource`` lists as live.
    ///
    /// - Parameter records: The registry's records, most recently active first.
    static func sessionIDsByTerminal(_ records: [AgentChatSessionRecord]) -> [UUID: String] {
        var byTerminal: [UUID: String] = [:]
        for record in records
        where record.agentKind == .claude && record.descriptor.kind == .agent && record.state != .ended {
            guard let terminal = record.descriptor.terminalID.flatMap(UUID.init(uuidString:)),
                  byTerminal[terminal] == nil else { continue }
            byTerminal[terminal] = record.sessionID
        }
        return byTerminal
    }

    // MARK: - The live change signal

    /// Watches the main windows and their workspaces, and calls `onChange` at most four times a second after
    /// a change.
    static func liveChangeSignal(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let observer = LiveWorkspaceChangeObserver(onChange: onChange)
        return { observer.stop() }
    }
}

/// Watches what ``ShellXLinkWorkspaceSource/liveWorkspaces()`` reads and calls `onChange` after a change, at most
/// four times a second (an agent's spinner in a tab title would otherwise send a phone ten whole lists a second;
/// the spec's target is a change on the phone within 500 ms), on the main actor: the set of main windows (`mainWindowContextsDidChange`), each window's
/// workspaces (`tabsPublisher`), each workspace (`objectWillChange`, plus what it keeps outside its `@Published`
/// properties: its panels, their spatial order, and the git branch in its sidebar metadata model), and the agent
/// session registry (the session a terminal names).
///
/// Every change goes through one throttle, after which the watched windows and workspaces are matched to the
/// current ones before `onChange` runs. The throttle delivers on a later main-queue turn, so a `willSet`-time
/// signal is read after the change has landed.
@MainActor
private final class LiveWorkspaceChangeObserver {
    /// One watched object. Weak, so a new object at a freed one's address is not taken for it.
    private struct Watch {
        weak var object: AnyObject?
        let cancellable: AnyCancellable
    }

    private let pulses = PassthroughSubject<Void, Never>()
    private var output: AnyCancellable?
    private var windowsObserver: (any NSObjectProtocol)?
    private var managers: [ObjectIdentifier: Watch] = [:]
    private var workspaces: [ObjectIdentifier: Watch] = [:]
    private var sessions: (service: AgentChatTranscriptService, token: UUID)?

    init(onChange: @escaping @MainActor () -> Void) {
        output = pulses
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else { return }
                attach()
                onChange()
            }
        windowsObserver = NotificationCenter.default.addObserver(
            forName: .mainWindowContextsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pulses.send() }
        }
        attach()
    }

    func stop() {
        output = nil
        if let windowsObserver { NotificationCenter.default.removeObserver(windowsObserver) }
        windowsObserver = nil
        managers.removeAll()
        workspaces.removeAll()
        if let sessions { sessions.service.removeFrameObserver(sessions.token) }
        sessions = nil
    }

    /// Watches the current windows and workspaces, and drops the watches of those that are gone.
    private func attach() {
        guard output != nil else { return }
        let windowManagers = ShellXLinkWorkspaceSource.mainWindowTabManagers()
        var current: [Workspace] = []
        var watchedManagers: [ObjectIdentifier: Watch] = [:]
        for manager in windowManagers {
            current.append(contentsOf: manager.tabs)
            let key = ObjectIdentifier(manager)
            if let watch = managers[key], watch.object === manager {
                watchedManagers[key] = watch
                continue
            }
            // A CurrentValueSubject: its replay on subscribe is not a change.
            watchedManagers[key] = Watch(object: manager, cancellable: manager.tabsPublisher.dropFirst().sink {
                [weak self] _ in self?.pulses.send()
            })
        }
        managers = watchedManagers

        var watchedWorkspaces: [ObjectIdentifier: Watch] = [:]
        for workspace in current {
            let key = ObjectIdentifier(workspace)
            if let watch = workspaces[key], watch.object === workspace {
                watchedWorkspaces[key] = watch
                continue
            }
            let changes = Publishers.Merge4(
                workspace.objectWillChange.map { _ in () },
                workspace.panelsPublisher.dropFirst().map { _ in () },
                workspace.paneLayoutVersionPublisher.dropFirst().map { _ in () },
                // A `git checkout` in the same directory changes only this.
                workspace.sidebarMetadata.gitBranchPublisher.dropFirst().map { _ in () }
            )
            watchedWorkspaces[key] = Watch(object: workspace, cancellable: changes.sink { [weak self] _ in
                self?.pulses.send()
            })
        }
        workspaces = watchedWorkspaces

        if sessions == nil, let service = TerminalController.shared.agentChatTranscriptService {
            let token = service.addFrameObserver { [weak self] frame in
                switch frame.event {
                case .stateChanged, .descriptorChanged, .sessionRemoved:
                    self?.pulses.send()
                case .appended, .updated, .terminalBlocks, .streamingProse, .reset, .unknown:
                    break
                }
            }
            sessions = (service, token)
        }
    }
}
