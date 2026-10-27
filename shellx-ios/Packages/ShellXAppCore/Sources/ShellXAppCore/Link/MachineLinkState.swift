import Foundation

/// Where the link to one Mac stands.
public enum MachineLinkState: Equatable, Sendable {
    /// The first attempt (or the first after the app came back) is under way.
    case connecting
    /// A live session, synced.
    case online
    /// The live session ended; trying to get it back. Pending items stay, but cannot be acted on.
    case reconnecting
    /// Could not reach the Mac since `since`; still retrying.
    case offline(since: Date)
    /// The Mac no longer lets this iPhone in. Stops the reconnect loop.
    case revoked
    /// The Mac's key is not the one pinned at pairing. Stops the reconnect loop.
    case hostKeyChanged
    /// The Mac speaks another protocol version. Stops the reconnect loop.
    case needsUpdate

    /// True for the three states that stop the reconnect loop for good.
    public var isTerminal: Bool {
        switch self {
        case .revoked, .hostKeyChanged, .needsUpdate: return true
        case .connecting, .online, .reconnecting, .offline: return false
        }
    }
}
