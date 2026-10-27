import Foundation
import ShellXLinkCore

/// Tells which sessions just finished a turn: working, or waiting on the user, when last seen, and
/// idle now. `HomeModel` saves it as `StoreDocument.lastSessions`, so a session that finished while
/// the app was closed is still reported on the next launch.
///
/// Each finish, a session's `(sessionId, stateSinceMs)` on one Mac, is reported once: a resync that
/// replays an older list and then the same finish (a reconnect, a restarted Mac app) stays quiet.
/// A session without `stateSinceMs` reports every change to idle, since a replay looks the same.
public struct SessionFinishDetector: Codable, Equatable, Sendable {
    /// A session's state when last seen.
    private struct Seen: Codable, Equatable {
        var state: AgentState
        var sinceMs: Int64?
    }

    /// One finish of one session.
    private struct Finish: Codable, Hashable {
        var sessionId: String
        var sinceMs: Int64
    }

    /// The last list seen from each Mac, by session.
    private var seen: [String: [String: Seen]] = [:]
    /// The finishes already reported, by Mac. Only sessions the Mac still lists are kept.
    private var reported: [String: Set<Finish>] = [:]

    public init() {}

    /// Takes the Mac's whole session list; returns the sessions that went from `working` or
    /// `needsInput` to `idle` since the last list from that Mac, in list order.
    public mutating func observe(machineID: String, sessions: [AgentSession]) -> [SessionRef] {
        let before = seen[machineID] ?? [:]
        var done = reported[machineID] ?? []
        var finished: [SessionRef] = []
        for session in sessions where session.state == .idle {
            guard let previous = before[session.sessionId], previous.state == .working || previous.state == .needsInput
            else { continue }
            // Without `stateSinceMs` a replay cannot be told from a new turn: every change is one.
            if let since = session.stateSinceMs {
                guard done.insert(Finish(sessionId: session.sessionId, sinceMs: since)).inserted else { continue }
            }
            finished.append(
                SessionRef(
                    machineID: machineID, sessionId: session.sessionId, agent: session.agent,
                    workspaceTitle: session.workspaceTitle))
        }
        let listed = Set(sessions.map(\.sessionId))
        reported[machineID] = done.filter { listed.contains($0.sessionId) }
        seen[machineID] = Dictionary(
            sessions.map { ($0.sessionId, Seen(state: $0.state, sinceMs: $0.stateSinceMs)) },
            uniquingKeysWith: { _, last in last })
        return finished
    }

    /// Forgets every Mac not in `machineIDs` (unpaired since).
    public mutating func retain(machineIDs: Set<String>) {
        seen = seen.filter { machineIDs.contains($0.key) }
        reported = reported.filter { machineIDs.contains($0.key) }
    }
}
