import ShellXAppCore

/// The screens pushed over the workspace list.
enum HomeRoute: Hashable {
    /// "Your Macs", from a Mac's header in the list and from Settings.
    case machines
    case settings
    /// Every pending card, from the "Needs you" bar and the bell.
    case pending
    /// One workspace's pending cards, from an agent screen's "Needs you" bar.
    case pendingIn(machineID: String, workspaceId: String)
    /// One workspace of a Mac.
    case workspace(WorkspaceRef)
    /// The sessions of a Mac that no workspace row accounts for.
    case otherSessions(machineID: String)
    /// The sessions that ended in the last hours, on every Mac, from the home's "Ended · N" fold.
    case ended
}
