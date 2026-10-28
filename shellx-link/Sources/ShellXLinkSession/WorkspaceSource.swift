import ShellXLinkCore

/// The host's list of workspaces (PROTOCOL.md section 4, "Workspace"): what `workspace.list` answers and
/// `workspace.changed` pushes. A host that has one offers the `workspaces` feature.
///
/// Its `revision` is a counter of its own, apart from the revisions of `AgentFeedSource` and
/// `AgentSessionSource`.
public protocol WorkspaceSource: Sendable {
    /// The current workspaces, in sidebar order, and their revision.
    func workspaces() async -> (revision: Int, workspaces: [LinkWorkspace])
    /// Every change of the workspace list from now on. A source MUST raise `revision` by exactly 1
    /// per change, and `workspaces()` at revision r includes every change up to r.
    ///
    /// Multicast, with the same lifetime and `onTermination` rules as `AgentFeedSource.changes()`:
    /// each call is a new subscriber, dropped when the consumer stops iterating, and
    /// `onTermination` must not take a lock that is held while calling `yield` or `finish`.
    func workspaceChanges() -> AsyncStream<(revision: Int, upserted: [LinkWorkspace], removed: [String])>
}

/// What a phone may do to the host's workspaces (PROTOCOL.md section 10): make one, rename one, close one.
/// A host that has one offers the `workspace_control` feature.
///
/// The implementation applies the host's own rules: it answers `.refused` when remote control is blocked or the
/// rule of the host forbids the action (closing the last workspace), `.notFound` for an id it does not have, and
/// `.failed` when it could not do it. It acts without changing the host's selection or bringing its window to the
/// front, and it never logs a workspace's title.
///
/// Calls arrive concurrently and may take a while; the host serves other calls meanwhile.
public protocol WorkspaceControl: Sendable {
    /// Makes a workspace. The host chooses its directory (a phone can name none) and the call carries nothing else.
    /// `workspaceId` is the new workspace's id when the outcome is `.ok`, and nil otherwise: the host does not send
    /// one with another outcome.
    func createWorkspace() async -> (outcome: WorkspaceControlOutcome, workspaceId: String?)
    /// Renames a workspace. `title` is at most `ShellXLink.maxWorkspaceTitleBytes` UTF-8 bytes; the host has checked it.
    func renameWorkspace(workspaceId: String, title: String) async -> WorkspaceControlOutcome
    func closeWorkspace(workspaceId: String) async -> WorkspaceControlOutcome
}
