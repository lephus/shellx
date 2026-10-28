import Foundation

/// One document the phone keeps on disk: one session's chat copy.
public enum StoreDocument: Hashable, Sendable {
    case thread(SessionRef)

    /// Short name for logs; never includes ids or content.
    var kind: String {
        switch self {
        case .thread: "thread"
        }
    }
}
