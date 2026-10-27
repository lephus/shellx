import Foundation
import ShellXLinkCore

/// One Mac's agent sessions at a revision, most recent activity first.
public struct SessionSet: Equatable, Sendable {
    public private(set) var revision: Int
    public private(set) var sessions: [AgentSession]

    public init(revision: Int = 0, sessions: [AgentSession] = []) {
        self.revision = revision
        self.sessions = Self.sorted(sessions)
    }

    /// Replaces the set with an `agent.sessions` answer.
    public mutating func reset(revision: Int, sessions: [AgentSession]) {
        self.revision = revision
        self.sessions = Self.sorted(sessions)
    }

    /// Applies an `agent.sessions.changed` when it is the next revision; otherwise leaves the set as
    /// it was and says why (PROTOCOL.md section 4).
    public mutating func apply(revision: Int, upserted: [AgentSession], removed: [String]) -> RevisionGate.Result {
        let result = RevisionGate.check(current: self.revision, incoming: revision)
        guard result == .applied else { return result }
        let replaced = Set(upserted.map(\.sessionId)).union(removed)
        let kept = sessions.filter { !replaced.contains($0.sessionId) }
        sessions = Self.sorted(kept + upserted.filter { !removed.contains($0.sessionId) })
        self.revision = revision
        return result
    }

    /// The session with `sessionId`, if the set has it.
    public func session(_ sessionId: String) -> AgentSession? {
        sessions.first { $0.sessionId == sessionId }
    }

    private static func sorted(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.sorted { a, b in
            let (lhs, rhs) = (a.lastActivityMs ?? .min, b.lastActivityMs ?? .min)
            return lhs != rhs ? lhs > rhs : a.sessionId < b.sessionId
        }
    }
}
