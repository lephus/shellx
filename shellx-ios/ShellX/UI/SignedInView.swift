import ShellXAppCore
import SwiftUI

/// The signed-in screens: `FirstMacView` while no Mac is paired, otherwise "Your Macs" (until the
/// main screen replaces it), Settings, and the pairing sheet.
struct SignedInView: View {
    let hub: MachineHub
    let email: String
    let inbox: PairingInbox
    let makePairing: @MainActor (MachineHub) -> PairingModel
    let signOut: () async -> Void

    @State private var pairing: PairingModel?
    @State private var showsPairing = false

    var body: some View {
        NavigationStack {
            Group {
                if hub.machines.isEmpty {
                    FirstMacView(pair: openPairing)
                } else {
                    MachinesView(hub: hub, pair: openPairing)
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
