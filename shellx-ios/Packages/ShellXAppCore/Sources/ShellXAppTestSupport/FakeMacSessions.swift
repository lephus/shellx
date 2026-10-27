import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// `FakeMac`'s agent sessions: an `AgentSessionSource` in memory.
final class FakeMacSessions: AgentSessionSource, @unchecked Sendable {
    typealias Change = (revision: Int, upserted: [AgentSession], removed: [String])

    private let lock = NSLock()
    private var byId: [String: AgentSession] = [:]
    private var revision = 0
    private var subscribers: [UUID: AsyncStream<Change>.Continuation] = [:]
    private var lists = 0

    var listCount: Int { lock.withLock { lists } }

    func upsert(_ session: AgentSession) {
        lock.withLock {
            byId[session.sessionId] = session
            broadcastLocked(upserted: [session], removed: [])
        }
    }

    func remove(_ sessionId: String) {
        lock.withLock {
            guard byId.removeValue(forKey: sessionId) != nil else { return }
            broadcastLocked(upserted: [], removed: [sessionId])
        }
    }

    /// Raises the revision without telling anyone, so the next change skips one.
    func skipRevision() {
        lock.withLock { revision += 1 }
    }

    func sessions() async -> (revision: Int, sessions: [AgentSession]) {
        lock.withLock {
            lists += 1
            return (revision, byId.values.sorted { $0.sessionId < $1.sessionId })
        }
    }

    func sessionChanges() -> AsyncStream<Change> {
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self)
        lock.withLock { subscribers[UUID()] = continuation }
        return stream
    }

    private func broadcastLocked(upserted: [AgentSession], removed: [String]) {
        revision += 1
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield((revision, upserted, removed)) { subscribers[id] = nil }
        }
    }
}
