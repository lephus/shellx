import ShellXAppCore

/// What the signed-in account's screens share: its hub, the decision center, the home model and
/// the pairing model. Made with the hub at every sign-in (`AppComposition`) and dropped with it.
@MainActor
final class SignedInScope {
    let hub: MachineHub
    let decisions: DecisionCenter
    let home: HomeModel
    let pairing: PairingModel
    private let launch: LaunchMark

    init(hub: MachineHub, decisions: DecisionCenter, home: HomeModel, pairing: PairingModel, launch: LaunchMark) {
        self.hub = hub
        self.decisions = decisions
        self.home = home
        self.pairing = pairing
        self.launch = launch
    }

    /// The home shows its conversation: records `launchToHome` once per launch.
    func homeShown() {
        launch.homeShown()
    }

    /// Holds the scope of the account signed in now.
    @MainActor
    final class Slot {
        var current: SignedInScope?

        /// The scope made with `hub`, if it is the current one.
        func scope(for hub: MachineHub) -> SignedInScope? {
            guard let current, current.hub === hub else { return nil }
            return current
        }
    }
}
