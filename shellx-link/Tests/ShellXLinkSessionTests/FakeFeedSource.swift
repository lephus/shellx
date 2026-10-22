import Foundation
import ShellXLinkCore
import ShellXLinkSession

typealias FeedChange = (revision: Int, added: [PendingItem], resolved: [String])

/// An in-memory `AgentFeedSource`: a dictionary of pending items plus a log of every call.
final class FakeFeedSource: AgentFeedSource, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String: PendingItem] = [:]
    private var resolved: Set<String> = []
    private var revision = 0
    private var subscribers: [UUID: AsyncStream<FeedChange>.Continuation] = [:]
    private var _snapshotCalls = 0
    private var _changesCalls = 0
    private var _replies: [(requestId: String, mode: PermissionMode)] = []
    private var _changeOnSubscribe = false
    /// Subscribers whose stream has terminated. Kept under its own lock: `onTermination` runs
    /// inside the runtime's cancellation path while `broadcastLocked` holds `lock` and yields,
    /// so taking `lock` there would invert lock order and deadlock.
    private let terminationLock = NSLock()
    private var terminated: Set<UUID> = []

    init(_ items: [PendingItem] = []) {
        for item in items { pending[item.requestId] = item }
    }

    var snapshotCalls: Int { lock.withLock { _snapshotCalls } }
    var changesCalls: Int { lock.withLock { _changesCalls } }
    var replies: [(requestId: String, mode: PermissionMode)] { lock.withLock { _replies } }
    var activeSubscribers: Int {
        let ids = lock.withLock { Set(subscribers.keys) }
        return ids.subtracting(terminationLock.withLock { terminated }).count
    }
    /// When true, every new subscriber at once gets a change adding one fresh item, as if the
    /// pending set changed at the moment of subscription.
    var changeOnSubscribe: Bool {
        get { lock.withLock { _changeOnSubscribe } }
        set { lock.withLock { _changeOnSubscribe = newValue } }
    }
    /// True when nothing has called the feed at all.
    var untouched: Bool { lock.withLock { _snapshotCalls == 0 && _changesCalls == 0 && _replies.isEmpty } }

    func add(_ items: PendingItem...) { add(items) }

    /// Adds every item in one change.
    func add(_ items: [PendingItem]) {
        lock.withLock {
            for item in items { pending[item.requestId] = item }
            broadcastLocked(added: items, resolved: [])
        }
    }

    /// Simulates the Mac answering a request itself.
    func resolveLocally(requestId: String) {
        lock.withLock {
            guard pending.removeValue(forKey: requestId) != nil else { return }
            resolved.insert(requestId)
            broadcastLocked(added: [], resolved: [requestId])
        }
    }

    func snapshot() async -> (revision: Int, pending: [PendingItem]) {
        lock.withLock {
            _snapshotCalls += 1
            return (revision, pending.values.sorted { $0.requestId < $1.requestId })
        }
    }

    func changes() -> AsyncStream<FeedChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: FeedChange.self)
        let id = UUID()
        lock.withLock {
            _changesCalls += 1
            subscribers[id] = continuation
            if _changeOnSubscribe {
                let item = permissionItem("sub-\(_changesCalls)")
                pending[item.requestId] = item
                broadcastLocked(added: [item], resolved: [])
            }
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.terminationLock.withLock { self.terminated.insert(id) }
        }
        return stream
    }

    func reply(requestId: String, mode: PermissionMode) async -> ReplyOutcome {
        lock.withLock {
            _replies.append((requestId, mode))
            if pending.removeValue(forKey: requestId) != nil {
                resolved.insert(requestId)
                broadcastLocked(added: [], resolved: [requestId])
                return .delivered
            }
            return resolved.contains(requestId) ? .alreadyHandled : .unknown
        }
    }

    private func broadcastLocked(added: [PendingItem], resolved: [String]) {
        revision += 1
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield((revision, added, resolved)) {
                subscribers[id] = nil
            }
        }
    }
}

func permissionItem(_ id: String, tool: String = "Bash", preview: String? = "ls -la") -> PendingItem {
    PendingItem(
        requestId: id, kind: .permission, agent: "claude", workspaceId: "ws-1", workspaceTitle: "shellx",
        toolName: tool, toolInputPreview: preview, createdAtMs: 1_700_000_000_000)
}

/// Delegates to a `FakeFeedSource`, but the first `reply` to each id in `slowIds` waits `delay`
/// first (a hook that is slow to resolve). Records what the feed answered to every call.
final class SlowFirstReplyFeed: AgentFeedSource, @unchecked Sendable {
    let base: FakeFeedSource
    private let slowIds: Set<String>
    private let delay: Duration
    private let lock = NSLock()
    private var seen: Set<String> = []
    private var _answers: [(requestId: String, mode: PermissionMode, outcome: ReplyOutcome)] = []

    init(_ base: FakeFeedSource, slowIds: Set<String>, delay: Duration) {
        self.base = base
        self.slowIds = slowIds
        self.delay = delay
    }

    var answers: [(requestId: String, mode: PermissionMode, outcome: ReplyOutcome)] { lock.withLock { _answers } }

    func snapshot() async -> (revision: Int, pending: [PendingItem]) { await base.snapshot() }

    func changes() -> AsyncStream<FeedChange> { base.changes() }

    func reply(requestId: String, mode: PermissionMode) async -> ReplyOutcome {
        let slow = lock.withLock { slowIds.contains(requestId) && seen.insert(requestId).inserted }
        if slow { try? await Task.sleep(for: delay) }
        let outcome = await base.reply(requestId: requestId, mode: mode)
        lock.withLock { _answers.append((requestId, mode, outcome)) }
        return outcome
    }
}
