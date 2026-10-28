import Foundation
import ShellXLinkCore

/// Tells which sessions just finished a turn: working, or waiting on the user, when last seen, and
/// idle now. `MachineHub` runs one over every session list a Mac sends, in memory only: what finished
/// while the app was closed is not reported on the next launch.
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
        reported[machineID] = Self.newest(done.filter { listed.contains($0.sessionId) })
        seen[machineID] = Dictionary(
            sessions.map { ($0.sessionId, Seen(state: $0.state, sinceMs: $0.stateSinceMs)) },
            uniquingKeysWith: { _, last in last })
        return finished
    }

    /// The newest `finishesKept` finishes of each session: a resync replays the current list, so
    /// older finishes cannot come back, and the saved detector stays small.
    private static func newest(_ finishes: Set<Finish>) -> Set<Finish> {
        let bySession = Dictionary(grouping: finishes, by: \.sessionId)
        return Set(bySession.values.flatMap { $0.sorted { $0.sinceMs > $1.sinceMs }.prefix(finishesKept) })
    }

    /// Finishes remembered per session.
    static let finishesKept = 2

    /// How many finishes are remembered for `machineID` (tests).
    func reportedCount(machineID: String) -> Int {
        reported[machineID]?.count ?? 0
    }

    /// Forgets every Mac not in `machineIDs` (unpaired since).
    public mutating func retain(machineIDs: Set<String>) {
        seen = seen.filter { machineIDs.contains($0.key) }
        reported = reported.filter { machineIDs.contains($0.key) }
    }
}
