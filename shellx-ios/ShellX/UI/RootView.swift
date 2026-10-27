import ShellXAppCore
import SwiftUI

/// Chooses the screen by the account phase: the logo while launching, sign-in, or the signed-in
/// screens.
struct RootView: View {
    let graph: AppGraph
    /// A `shellx-link://` link opened from outside, held until a signed-in screen takes it.
    let inbox: PairingInbox

    private var coordinator: AppCoordinator { graph.coordinator }

    var body: some View {
        switch coordinator.phase {
        case .launching:
            LaunchView()
        case let .signedOut(expired):
            SignInView(coordinator: coordinator, expired: expired)
        case let .signedIn(email):
            if let hub = coordinator.hub, hub.isLoaded {
                SignedInView(
                    hub: hub, email: email, inbox: inbox, makePairing: graph.makePairing,
                    signOut: { await coordinator.signOut() }
                )
                .id(ObjectIdentifier(hub))
            } else {
                LaunchView()
            }
        }
    }
}

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

/// The ShellX logo and name.
struct LaunchView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .accessibilityHidden(true)
            Text(LocalizedStringResource("root.title"))
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

#if DEBUG
#Preview {
    RootView(graph: .preview(), inbox: PairingInbox())
}
#endif
