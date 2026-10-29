import Foundation
import ShellXLinkCore
import ShellXLinkSession

typealias SessionChange = (revision: Int, upserted: [AgentSession], removed: [String])

/// An in-memory `AgentSessionSource`: a dictionary of sessions plus a revision counter.
final class FakeSessionSource: AgentSessionSource, @unchecked Sendable {
    private let lock = NSLock()
    private var byId: [String: AgentSession] = [:]
    private var revision = 0
    private var subscribers: [UUID: AsyncStream<SessionChange>.Continuation] = [:]
    private var _sessionsCalls = 0
    private var _changesCalls = 0
    /// Subscribers whose stream has terminated (own lock, see `FakeFeedSource`).
    private let terminationLock = NSLock()
    private var terminated: Set<UUID> = []

    init(_ sessions: [AgentSession] = []) {
        for session in sessions { byId[session.sessionId] = session }
    }

    var sessionsCalls: Int { lock.withLock { _sessionsCalls } }
    var changesCalls: Int { lock.withLock { _changesCalls } }
    var activeSubscribers: Int {
        let ids = lock.withLock { Set(subscribers.keys) }
        return ids.subtracting(terminationLock.withLock { terminated }).count
    }

    func upsert(_ sessions: AgentSession...) {
        lock.withLock {
            for session in sessions { byId[session.sessionId] = session }
            broadcastLocked(upserted: sessions, removed: [])
        }
    }

    func remove(_ sessionId: String) {
        lock.withLock {
            guard byId.removeValue(forKey: sessionId) != nil else { return }
            broadcastLocked(upserted: [], removed: [sessionId])
        }
    }

    /// Raises the revision without telling anyone: the next change then skips a revision.
    func skipRevision() {
        lock.withLock { revision += 1 }
    }

    func sessions() async -> (revision: Int, sessions: [AgentSession]) {
        lock.withLock {
            _sessionsCalls += 1
            return (revision, byId.values.sorted { $0.sessionId < $1.sessionId })
        }
    }

    func sessionChanges() -> AsyncStream<SessionChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionChange.self)
        let id = UUID()
        lock.withLock {
            _changesCalls += 1
            subscribers[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.terminationLock.withLock { self.terminated.insert(id) }
        }
        return stream
    }

    private func broadcastLocked(upserted: [AgentSession], removed: [String]) {
        revision += 1
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield((revision, upserted, removed)) {
                subscribers[id] = nil
            }
        }
    }
}

func agentSession(
    _ id: String, state: AgentState = .idle, title: String? = nil, workspaceTitle: String = "shellx"
) -> AgentSession {
    AgentSession(
        sessionId: id, agent: "claude", workspaceId: "ws-\(id)", workspaceTitle: workspaceTitle, title: title,
        state: state, stateSinceMs: 1_700_000_000_000, lastActivityMs: 1_700_000_001_000)
}
