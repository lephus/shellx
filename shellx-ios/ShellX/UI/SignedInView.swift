import ShellXAppCore
import SwiftUI

/// The signed-in screens: `FirstMacView` while no Mac is paired, otherwise the workspace list (the
/// home), with "Your Macs", Settings, every pending card, a workspace and the other agent sessions
/// pushed over it, and the pairing sheet.
///
/// It owns the account's background work while it is on screen: the decision center follows the
/// hub's pending items here (the one place that calls `sync`), and the chat copy sweeper watches the
/// hub for transcript resets.
struct SignedInView: View {
    let scope: SignedInScope
    let email: String
    let inbox: PairingInbox
    let signOut: () async -> Void

    @State private var path = NavigationPath()
    @State private var showsPairing = false
    @Environment(\.scenePhase) private var scenePhase

    private var hub: MachineHub { scope.hub }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hub.machines.isEmpty {
                    FirstMacView(pair: openPairing)
                        .toolbar {
                            // Where the list has it.
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { path.append(HomeRoute.settings) } label: {
                                    Label(String(localized: "settings.title"), systemImage: "gearshape")
                                }
                                .accessibilityIdentifier("root.settings")
                            }
                        }
                } else {
                    WorkspaceListView(scope: scope, open: { path.append($0) })
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .machines:
                    MachinesView(hub: hub, pair: openPairing)
                case .settings:
                    SettingsView(email: email, signOut: signOut)
                case .pending:
                    PendingListView(hub: hub, center: scope.decisions)
                case let .pendingIn(machineID, workspaceId):
                    PendingListView(
                        hub: hub, center: scope.decisions,
                        only: { $0.isIn(machineID: machineID, workspaceId: workspaceId) })
                case let .workspace(ref):
                    WorkspaceView(scope: scope, ref: ref, open: { path.append($0) })
                case let .otherSessions(machineID):
                    OtherSessionsView(hub: hub, machineID: machineID)
                }
            }
        }
        // Every mic below (the composers, the question and plan sheets) and Settings › Voice.
        .environment(scope.voice)
        // Every pending sheet below counts itself here.
        .environment(scope.sheets)
        .sheet(isPresented: $showsPairing, onDismiss: { scope.pairing.cancel() }) {
            PairingSheet(model: scope.pairing, close: { showsPairing = false })
        }
        .onAppear {
            takeLink()
            scope.decisions.sync(hub.pendingItems)
        }
        .onChange(of: inbox.hasLink) { takeLink() }
        // A link that came while a pending sheet was up shows once the last one closed.
        .onChange(of: scope.sheets.isAnyOpen) { _, open in
            if !open { takeLink() }
        }
        // The center follows the hub's whole list here, outside any body; the cards only read it.
        .onChange(of: hub.pendingItems) { _, items in scope.decisions.sync(items) }
        .task { await scope.chatCopies.run() }
        // Leaving the foreground stops every mic, in touch and in VoiceOver tap mode alike.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, let voice = scope.voice else { return }
            Task { await voice.cancelAll() }
        }
    }

    private func openPairing() {
        scope.pairing.cancel()
        showsPairing = true
    }

    /// A link opened from elsewhere goes to the confirmation step, never straight to pairing. While
    /// a pending sheet is up the link waits in the inbox: the pairing sheet cannot show over it, and
    /// closing it would lose an answer being typed.
    private func takeLink() {
        guard let uri = inbox.take(over: scope.sheets) else { return }
        scope.pairing.begin(uri: uri)
        showsPairing = true
    }
}
