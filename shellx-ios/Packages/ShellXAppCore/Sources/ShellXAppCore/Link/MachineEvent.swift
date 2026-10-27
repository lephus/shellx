import Foundation
import ShellXLinkCore

/// What a `MachineConnection` reports, in order.
public enum MachineEvent: Sendable {
    case state(MachineLinkState)
    /// The pending set. `actionable` is false whenever the set is not backed by a live, synced session.
    case pending(PendingSet, actionable: Bool)
    /// The session list. `supported` is false when the Mac has no session list (an older ShellX).
    case sessions(SessionSet, supported: Bool)
    /// New or changed chat entries of one session (upserts by `ChatEntry.id`).
    case chat(sessionId: String, entries: [ChatEntry])
    /// The session's transcript was replaced (`chat.reset`), in order with its `chat` events.
    case chatReset(sessionId: String)
    /// The relay refused the account token. The connection has stopped; the owner signs the user out.
    case signedOut
}
