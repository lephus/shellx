import ShellXAppCore

/// What the signed-in account's screens share: its hub, the decision center, the home model, the
/// pairing model and the history store. Made with the hub at every sign-in (`AppComposition`) and
/// dropped with it.
@MainActor
final class SignedInScope {
    let hub: MachineHub
    let decisions: DecisionCenter
    let home: HomeModel
    let pairing: PairingModel
    /// Where each agent's chat copy is kept (wiped on sign-out).
    let history: ConversationStore
    private let launch: LaunchMark

    init(
        hub: MachineHub, decisions: DecisionCenter, home: HomeModel, pairing: PairingModel,
        history: ConversationStore, launch: LaunchMark
    ) {
        self.hub = hub
        self.decisions = decisions
        self.home = home
        self.pairing = pairing
        self.history = history
        self.launch = launch
    }

    /// The model of one agent's screen, over this account's hub and history.
    func agentThread(_ ref: SessionRef) -> AgentThreadModel {
        AgentThreadModel(ref: ref, hub: hub, store: history)
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
