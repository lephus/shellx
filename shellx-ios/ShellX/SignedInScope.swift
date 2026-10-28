import ShellXAppCore

/// What the signed-in account's screens share: its hub, the decision center, the pairing model, the
/// history store and the sweeper of its stale copies, the voice input and the count of open sheets.
/// Made with the hub at every sign-in (`AppComposition`) and dropped with it.
@MainActor
final class SignedInScope {
    let hub: MachineHub
    let decisions: DecisionCenter
    let pairing: PairingModel
    /// Where each agent's chat copy is kept (wiped on sign-out).
    let history: ConversationStore
    /// Drops a chat copy when its Mac resets the transcript, whether or not its screen is open.
    let chatCopies: ChatCopySweeper
    /// The mic's models and settings; nil shows no mic (render tests, previews).
    let voice: VoiceService?
    /// The pending sheets open now: a pairing link waits until none is.
    let sheets: SheetPresence
    private let launch: LaunchMark

    init(
        hub: MachineHub, decisions: DecisionCenter, pairing: PairingModel, history: ConversationStore,
        launch: LaunchMark, voice: VoiceService? = nil, sheets: SheetPresence = SheetPresence()
    ) {
        self.hub = hub
        self.decisions = decisions
        self.pairing = pairing
        self.history = history
        chatCopies = ChatCopySweeper(hub: hub, store: history)
        self.launch = launch
        self.voice = voice
        self.sheets = sheets
    }

    /// The model of one agent's screen, over this account's hub and history.
    func agentThread(_ ref: SessionRef) -> AgentThreadModel {
        AgentThreadModel(ref: ref, hub: hub, store: history)
    }

    /// The workspace list is shown: records `launchToHome` once per launch.
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
