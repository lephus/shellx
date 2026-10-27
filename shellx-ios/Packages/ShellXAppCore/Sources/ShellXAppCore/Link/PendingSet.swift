import Foundation
import ShellXLinkCore

/// One Mac's pending requests at a revision, oldest first (by `createdAtMs`).
public struct PendingSet: Equatable, Sendable {
    public private(set) var revision: Int
    public private(set) var items: [PendingItem]

    public init(revision: Int = 0, items: [PendingItem] = []) {
        self.revision = revision
        self.items = Self.sorted(items)
    }

    /// Replaces the set with a snapshot.
    public mutating func reset(revision: Int, items: [PendingItem]) {
        self.revision = revision
        self.items = Self.sorted(items)
    }

    /// Applies an `agent.changed` when it is the next revision; otherwise leaves the set as it was
    /// and says why (PROTOCOL.md section 4).
    public mutating func apply(revision: Int, added: [PendingItem], resolved: [String]) -> RevisionGate.Result {
        let result = RevisionGate.check(current: self.revision, incoming: revision)
        guard result == .applied else { return result }
        let replaced = Set(added.map(\.requestId)).union(resolved)
        items = Self.sorted(items.filter { !replaced.contains($0.requestId) } + added.filter { !resolved.contains($0.requestId) })
        self.revision = revision
        return result
    }

    private static func sorted(_ items: [PendingItem]) -> [PendingItem] {
        items.sorted { ($0.createdAtMs, $0.requestId) < ($1.createdAtMs, $1.requestId) }
    }
}
