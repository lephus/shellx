import Foundation
import ShellXLinkCore

/// One live session in the home's "Agents · N" strip: where it runs, its state, and how long that
/// state has lasted.
public struct AgentStatusRow: Equatable, Identifiable, Sendable {
    public var ref: SessionRef
    public var machineName: String
    public var state: AgentState
    /// Whether the session's Mac is online; an offline Mac's sessions are its last known ones.
    public var online: Bool
    /// Now minus `stateSinceMs`, never negative (the Mac's clock may run ahead of the phone's); nil
    /// when the Mac did not say when the state began.
    public var elapsed: Duration?

    public var id: SessionRef { ref }

    public init(session: MachineSession, now: Date) {
        ref = session.ref
        machineName = session.machineName
        state = session.session.state
        online = session.online
        elapsed = session.session.stateSinceMs.map { since in
            let nowMs = Int64((now.timeIntervalSince1970 * 1000).rounded())
            return .milliseconds(Swift.max(0, nowMs - since))
        }
    }

    /// The rows for `sessions`: needs you first, then running, then done (idle), then any state this
    /// app does not know; within each, the most recently active first.
    public static func rows(_ sessions: [MachineSession], now: Date) -> [AgentStatusRow] {
        sessions
            .sorted { a, b in
                let (lhs, rhs) = (rank(a.session.state), rank(b.session.state))
                if lhs != rhs { return lhs < rhs }
                let (aActivity, bActivity) = (a.session.lastActivityMs ?? .min, b.session.lastActivityMs ?? .min)
                if aActivity != bActivity { return aActivity > bActivity }
                return (a.machineID, a.session.sessionId) < (b.machineID, b.session.sessionId)
            }
            .map { AgentStatusRow(session: $0, now: now) }
    }

    private static func rank(_ state: AgentState) -> Int {
        switch state {
        case .needsInput: return 0
        case .working: return 1
        case .idle: return 2
        case .ended, .other: return 3
        }
    }
}
