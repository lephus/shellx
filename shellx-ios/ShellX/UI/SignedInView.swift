import ShellXAppCore
import SwiftUI

/// The signed-in screens: `FirstMacView` while no Mac is paired, otherwise "Your Macs" with the
/// pending cards (until the main screen replaces it), Settings, and the pairing sheet.
struct SignedInView: View {
    let hub: MachineHub
    let email: String
    let inbox: PairingInbox
    let makePairing: @MainActor (MachineHub) -> PairingModel
    let signOut: () async -> Void

    @State private var pairing: PairingModel?
    @State private var showsPairing = false
    /// One per hub: the view is rebuilt (`.id`) for a new hub.
    @State private var decisions: DecisionCenter

    init(
        hub: MachineHub, email: String, inbox: PairingInbox,
        makePairing: @escaping @MainActor (MachineHub) -> PairingModel,
        makeDecisions: @MainActor (MachineHub) -> DecisionCenter, signOut: @escaping () async -> Void
    ) {
        self.hub = hub
        self.email = email
        self.inbox = inbox
        self.makePairing = makePairing
        self.signOut = signOut
        _decisions = State(initialValue: makeDecisions(hub))
    }

    var body: some View {
        NavigationStack {
            Group {
                if hub.machines.isEmpty {
                    FirstMacView(pair: openPairing)
                } else {
                    MachinesView(hub: hub, center: decisions, pair: openPairing)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(email: email, signOut: signOut)
                    } label: {
                        Label(String(localized: "settings.title"), systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("root.settings")
                }
            }
        }
        .sheet(isPresented: $showsPairing, onDismiss: { pairing?.cancel() }) {
            if let pairing {
                PairingSheet(model: pairing, close: { showsPairing = false })
            }
        }
        .onAppear(perform: takeLink)
        .onChange(of: inbox.hasLink) { takeLink() }
    }

    private func model() -> PairingModel {
        if let pairing { return pairing }
        let made = makePairing(hub)
        pairing = made
        return made
    }

    private func openPairing() {
        model().cancel()
        showsPairing = true
    }

    /// A link opened from elsewhere goes to the confirmation step, never straight to pairing.
    private func takeLink() {
        guard let uri = inbox.take() else { return }
        model().begin(uri: uri)
        showsPairing = true
    }
}
