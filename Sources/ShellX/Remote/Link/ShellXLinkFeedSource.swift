import CMUXAgentLaunch
import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// ShellX: ShellX Link's view of the agent Feed: the pending permission requests in `FeedCoordinator`'s
/// store, their changes, and replies that resolve them through `FeedCoordinator.deliverReply`.
///
/// * The pending set is every `.pending` `.permissionRequest` item (P1 answers permissions only).
/// * `revision` counts changes of that set: it rises by exactly 1 per `agent.changed` (PROTOCOL.md 4), so a
///   phone resyncs only when it really missed one. It starts at the store's revision, which never runs
///   behind an earlier session's count after a relaunch.
/// * Every `changes()` call is a new subscriber, dropped when its stream ends. While nobody subscribes,
///   no Feed revision observer runs; ``snapshot()`` catches the set up on demand.
///
/// All state is main-actor isolated, like the store. `onTermination` only schedules the removal on the
/// main actor, so it never waits for anything `yield` holds.
@MainActor
final class ShellXLinkFeedSource: AgentFeedSource {
    /// The workspace a Feed item belongs to, or nil when no live workspace owns it.
    typealias WorkspaceLookup = @MainActor (WorkstreamItem) -> (id: String, title: String)?
    typealias Change = (revision: Int, added: [PendingItem], resolved: [String])

    private let coordinator: FeedCoordinator
    private let workspaceLookup: WorkspaceLookup
    private var subscribers: [UUID: AsyncStream<Change>.Continuation] = [:]
    /// Streams that ended before their subscription ran; never subscribed afterwards.
    private var endedEarly: Set<UUID> = []
    private var revisionObserver: UUID?
    /// Workspace lookups by `workstreamId`, kept while that workstream has a pending item: the default
    /// lookup reads hook-session files on the main actor. A miss is not cached, so a session file written
    /// later is still found.
    private var workspaces: [String: (id: String, title: String)] = [:]
    /// The pending set as last published, in Feed order.
    private var published: [PendingItem] = []
    private var revision: Int?

    /// - Parameters:
    ///   - coordinator: The app's Feed coordinator (its installed store may change).
    ///   - workspaceLookup: Finds an item's workspace; the default asks the agent hook session records and the
    ///     open windows. Tests pass a fixed answer.
    init(coordinator: FeedCoordinator, workspaceLookup: @escaping WorkspaceLookup = ShellXLinkFeedSource.liveWorkspace) {
        self.coordinator = coordinator
        self.workspaceLookup = workspaceLookup
    }

    /// Live subscriptions (tests).
    var subscriberCount: Int { subscribers.count }

    // MARK: - AgentFeedSource

    func snapshot() async -> (revision: Int, pending: [PendingItem]) {
        refresh()
        return (revision ?? 0, published)
    }

    nonisolated func changes() -> AsyncStream<(revision: Int, added: [PendingItem], resolved: [String])> {
        let (stream, continuation) = AsyncStream<Change>.makeStream(bufferingPolicy: .unbounded)
        let id = UUID()
        // Synchronous from cancellation, `finish()` or release: only schedule the removal.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.unsubscribe(id) }
        }
        // `LinkHost` subscribes before `welcome` and asks for a snapshot after it; that snapshot's main-actor
        // hop runs after this one, so the phone's starting point precedes every change it is sent.
        Task { @MainActor in self.subscribe(id, continuation) }
        return stream
    }

    func reply(requestId: String, mode: PermissionMode) async -> ReplyOutcome {
        resolveReply(requestId: requestId, mode: mode)
    }

    /// ``reply(requestId:mode:)`` without the suspension: decides and resolves in one main-actor turn.
    func resolveReply(requestId: String, mode: PermissionMode) -> ReplyOutcome {
        guard let store = coordinator.store,
              let item = store.items.last(where: { $0.payload.requestID == requestId }) else {
            return .unknown
        }
        // Resolved here, by another phone, or on the Mac (Feed panel, notification, `feed.*.reply`). The
        // registry check also covers a socket-thread reply whose store update has not reached the main actor.
        guard item.status.isPending, !coordinator.waiterRegistry.hasDecision(requestId) else {
            return .alreadyHandled
        }
        guard case .permissionRequest(_, _, let toolInputJSON, _) = item.payload,
              let decision = Self.permissionMode(mode),
              Self.allows(decision, source: item.source, toolInputJSON: toolInputJSON) else {
            return .unknown
        }
        // No hook waits (a card restored from the Feed log): nothing would receive the decision.
        guard coordinator.waiterRegistry.isAwaiting(requestId) else { return .alreadyHandled }
        // On the main actor `deliverReply` marks the item resolved synchronously, so subscribers see the
        // change before this returns. It never waits on the hook. It is first-wins: when another entry point
        // took the waiter since the checks above, the phone hears `already_handled`.
        return coordinator.deliverReply(requestId: requestId, decision: .permission(decision))
            ? .delivered : .alreadyHandled
    }

    // MARK: - Subscriptions

    private func subscribe(_ id: UUID, _ continuation: AsyncStream<Change>.Continuation) {
        guard endedEarly.remove(id) == nil else { return }
        if subscribers.isEmpty {
            refresh()   // catch up while nobody listened, before this subscriber's first change
            revisionObserver = coordinator.addRevisionObserver { [weak self] _ in self?.refresh() }
        }
        subscribers[id] = continuation
    }

    private func unsubscribe(_ id: UUID) {
        guard subscribers.removeValue(forKey: id) != nil else {
            endedEarly.insert(id)
            return
        }
        guard subscribers.isEmpty, let token = revisionObserver else { return }
        coordinator.removeRevisionObserver(token)
        revisionObserver = nil
    }

    /// Compares the store's pending set with the published one and publishes the difference, if any.
    private func refresh() {
        let items = coordinator.store?.items ?? []
        if revision == nil { revision = coordinator.store?.revision ?? 0 }
        let known = Dictionary(published.map { ($0.requestId, $0) }, uniquingKeysWith: { first, _ in first })
        var current: [PendingItem] = []
        var added: [PendingItem] = []
        var seen = Set<String>()
        for item in items where item.status.isPending {
            guard case .permissionRequest(let requestId, let toolName, let toolInputJSON, _) = item.payload,
                  seen.insert(requestId).inserted else {
                continue
            }
            if let existing = known[requestId] {
                current.append(existing)
            } else {
                let pending = makePendingItem(item, requestId: requestId, toolName: toolName, toolInputJSON: toolInputJSON)
                current.append(pending)
                added.append(pending)
            }
        }
        let pendingWorkstreams = Set(items.lazy.filter { $0.status.isPending }.map(\.workstreamId))
        workspaces = workspaces.filter { pendingWorkstreams.contains($0.key) }
        let resolved = published.map(\.requestId).filter { !seen.contains($0) }
        guard !added.isEmpty || !resolved.isEmpty else { return }
        let next = (revision ?? 0) + 1
        revision = next
        published = current
        for continuation in subscribers.values {
            continuation.yield((revision: next, added: added, resolved: resolved))
        }
    }

    private func makePendingItem(_ item: WorkstreamItem, requestId: String, toolName: String,
                                 toolInputJSON: String) -> PendingItem {
        let workspace = workspaces[item.workstreamId] ?? workspaceLookup(item)
        if let workspace { workspaces[item.workstreamId] = workspace }
        let fallbackTitle = item.title ?? item.cwd.map { ($0 as NSString).lastPathComponent } ?? ""
        return PendingItem(
            requestId: requestId,
            kind: .permission,
            agent: item.sourceID ?? item.source.rawValue,
            workspaceId: workspace?.id ?? item.workstreamId,
            workspaceTitle: workspace?.title ?? fallbackTitle,
            toolName: toolName,
            toolInputPreview: PendingItem.truncatedPreview(toolInputJSON),
            createdAtMs: Int64((item.createdAt.timeIntervalSince1970 * 1000).rounded())
        )
    }

    // MARK: - Mapping

    /// ShellX Link modes map to Feed modes by name (`bypass` has no Link mode).
    static func permissionMode(_ mode: PermissionMode) -> WorkstreamPermissionMode? {
        WorkstreamPermissionMode(rawValue: mode.rawValue)
    }

    /// The modes the Feed panel offers for this agent and request (`FeedPermissionActionPolicy`).
    static func allows(_ mode: WorkstreamPermissionMode, source: WorkstreamSource, toolInputJSON: String) -> Bool {
        switch mode {
        case .deny: return true
        case .once: return FeedPermissionActionPolicy.supportsOncePermissionMode(source: source, toolInputJSON: toolInputJSON)
        case .always: return FeedPermissionActionPolicy.supportsAlwaysPermissionMode(source: source, toolInputJSON: toolInputJSON)
        case .all: return FeedPermissionActionPolicy.supportsAllPermissionMode(source: source, toolInputJSON: toolInputJSON)
        case .bypass: return FeedPermissionActionPolicy.supportsBypassPermissions(source: source)
        }
    }

    /// The workspace recorded by the agent's hook session, titled from the open window that owns it.
    static func liveWorkspace(_ item: WorkstreamItem) -> (id: String, title: String)? {
        guard let target = FeedJumpResolver.resolve(item.workstreamId) else { return nil }
        let title = UUID(uuidString: target.workspaceId).flatMap { id in
            AppDelegate.shared?.tabManagerFor(tabId: id)?.workspacesById[id]?.title
        }
        return (target.workspaceId, title ?? item.title ?? "")
    }
}
