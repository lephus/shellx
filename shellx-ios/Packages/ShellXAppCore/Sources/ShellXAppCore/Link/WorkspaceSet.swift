import Foundation
import ShellXLinkCore

/// One Mac's workspaces at a revision, in the order of the Mac's sidebar.
///
/// The revision is the workspace list's own counter, apart from the pending set's and the session
/// list's (PROTOCOL.md section 4, "Workspace").
public struct WorkspaceSet: Equatable, Sendable {
    public private(set) var revision: Int
    public private(set) var workspaces: [LinkWorkspace]

    public init(revision: Int = 0, workspaces: [LinkWorkspace] = []) {
        self.revision = revision
        self.workspaces = Self.sorted(workspaces)
    }

    /// Replaces the set with a `workspace.list` answer.
    public mutating func reset(revision: Int, workspaces: [LinkWorkspace]) {
        self.revision = revision
        self.workspaces = Self.sorted(workspaces)
    }

    /// Applies a `workspace.changed` when it is the next revision; otherwise leaves the set as it
    /// was and says why (PROTOCOL.md section 4). An upsert replaces the workspace with the same id,
    /// terminals and all.
    public mutating func apply(revision: Int, upserted: [LinkWorkspace], removed: [String]) -> RevisionGate.Result {
        let result = RevisionGate.check(current: self.revision, incoming: revision)
        guard result == .applied else { return result }
        let replaced = Set(upserted.map(\.workspaceId)).union(removed)
        let kept = workspaces.filter { !replaced.contains($0.workspaceId) }
        workspaces = Self.sorted(kept + upserted.filter { !removed.contains($0.workspaceId) })
        self.revision = revision
        return result
    }

    /// The workspace with `id`, if the set has it.
    public func workspace(_ id: String) -> LinkWorkspace? {
        workspaces.first { $0.workspaceId == id }
    }

    /// By `order`; two workspaces at the same position (windows count apart) by id, so the list does
    /// not shuffle between two answers.
    private static func sorted(_ workspaces: [LinkWorkspace]) -> [LinkWorkspace] {
        workspaces.sorted { ($0.order, $0.workspaceId) < ($1.order, $1.workspaceId) }
    }
}
