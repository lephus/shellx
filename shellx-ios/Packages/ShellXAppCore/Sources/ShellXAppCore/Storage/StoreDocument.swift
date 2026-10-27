import Foundation

/// One document the phone keeps on disk: the home timeline, the last-seen session state, or one
/// session's chat copy.
public enum StoreDocument: Hashable, Sendable {
    case home
    case lastSessions
    case thread(SessionRef)

    /// Short name for logs; never includes ids or content.
    var kind: String {
        switch self {
        case .home: "home"
        case .lastSessions: "last_sessions"
        case .thread: "thread"
        }
    }
}
