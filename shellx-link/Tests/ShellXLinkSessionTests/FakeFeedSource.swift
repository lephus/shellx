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

    init(_ items: [PendingItem] = []) {
        for item in items { pending[item.requestId] = item }
    }

    var snapshotCalls: Int { lock.withLock { _snapshotCalls } }
    var changesCalls: Int { lock.withLock { _changesCalls } }
    var replies: [(requestId: String, mode: PermissionMode)] { lock.withLock { _replies } }
    var activeSubscribers: Int { lock.withLock { subscribers.count } }
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
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.lock.withLock { self.subscribers.removeValue(forKey: id) }
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
        for continuation in subscribers.values {
            continuation.yield((revision, added, resolved))
        }
    }
}

func permissionItem(_ id: String, tool: String = "Bash", preview: String? = "ls -la") -> PendingItem {
    PendingItem(
        requestId: id, kind: .permission, agent: "claude", workspaceId: "ws-1", workspaceTitle: "shellx",
        toolName: tool, toolInputPreview: preview, createdAtMs: 1_700_000_000_000)
}
