import Foundation

/// The revision rule of ShellX Link (PROTOCOL.md section 4) for the pending set and the session list.
public enum RevisionGate {
    public enum Result: Equatable, Sendable {
        /// The change is the next one: apply it.
        case applied
        /// The change is at or below the current revision: it is already in the set.
        case ignored
        /// One or more changes were missed: ask the host for the full set again.
        case gap
    }

    /// How a change at revision `incoming` relates to a set at revision `current`.
    public static func check(current: Int, incoming: Int) -> Result {
        if incoming <= current { return .ignored }
        return incoming == current + 1 ? .applied : .gap
    }
}
