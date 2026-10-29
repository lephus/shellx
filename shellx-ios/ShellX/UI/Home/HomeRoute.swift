/// The screens pushed over the home.
enum HomeRoute: Hashable {
    /// "Your Macs", from the Mac in the toolbar.
    case machines
    case settings
    /// Every pending card, from the home's "Needs you" bar.
    case pending
    /// One workspace's pending cards, from an agent screen's "Needs you" bar.
    case pendingIn(machineID: String, workspaceId: String)
}
