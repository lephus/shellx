import Foundation
import ShellXLinkCore

/// How a workspace command (make, rename, close) went, as `MachineHub` reports it.
public enum WorkspaceCommandResult: Equatable, Sendable {
    /// The Mac did it. `workspaceId` is the new workspace's id after a create, nil for the others.
    case ok(workspaceId: String?)
    /// The Mac has no workspace with that id.
    case notFound
    /// The Mac does not allow it: remote control is blocked, or its own rule says no (a pinned workspace,
    /// or the last workspace of a window, stays).
    case refused
    /// The Mac could not do it, or took no such command.
    case failed
    /// The Mac is not online: nothing was sent.
    case offline
    /// The command was sent but the answer is not known: the link dropped while waiting, or the Mac
    /// answered in a way this app does not know. It is not sent again (the Mac may have acted); the
    /// workspace list tells what became of it.
    case unknown

    /// The result for the Mac's `outcome` and, for a create, the id of the new workspace.
    init(outcome: WorkspaceControlOutcome, workspaceId: String? = nil) {
        switch outcome {
        case .ok: self = .ok(workspaceId: workspaceId)
        case .notFound: self = .notFound
        case .refused: self = .refused
        case .failed: self = .failed
        case .other: self = .unknown
        }
    }
}
