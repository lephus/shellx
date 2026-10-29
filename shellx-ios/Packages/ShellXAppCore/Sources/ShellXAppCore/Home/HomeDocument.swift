import Foundation

/// What `HomeModel` keeps in `StoreDocument.home`.
struct HomeDocument: Codable, Sendable {
    var entries: [HomeEntry]
    /// The session the last message went to: the composer's default while it runs.
    var lastUsed: SessionRef?
}
