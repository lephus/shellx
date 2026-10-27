import ShellXAppCore
import SwiftUI

/// The main screen, "ShellX" (plan decision D7), fed by the signed-in scope: the pinned cards from
/// the decision center (its owner, `SignedInView`, keeps it synced with the hub), the agent rows
/// and the conversation from the home model, and the composer that sends through it.
struct HomeView: View {
    let scope: SignedInScope
    /// Pushes a screen over the home.
    let open: (HomeRoute) -> Void

    @State private var route: PendingRoute?
    @State private var draft = ""
    @AppStorage("shellx.home.agentsExpanded") private var agentsExpanded = true

    var body: some View {
        let hub = scope.hub
        let center = scope.decisions
        let home = scope.home
        let sessions = hub.liveSessions
        let defaultMachine = hub.machines.first { $0.id == hub.defaultMachineID }
        let picked = home.target.flatMap { target in sessions.contains { $0.ref == target } ? target : nil }
        HomeScreen(
            machine: defaultMachine.map { (name: $0.name, state: $0.state) },
            pending: center.visibleItems(hub.pendingItems),
            pendingStatus: center.status,
            showsMachineName: hub.machines.count > 1,
            rows: { home.statusRows },
            entries: home.entries,
            target: home.effectiveTarget,
            pickedTarget: picked,
            sessions: sessions,
            draft: $draft,
            agentsExpanded: $agentsExpanded,
            actions: HomeScreen.Actions(
                openMachines: { open(.machines) },
                openSettings: { open(.settings) },
                seeAllPending: { open(.pending) },
                choose: { home.target = $0 },
                send: { text in Task { _ = await home.submit(text, viaVoice: false) } },
                card: { item in PendingCardsSection.actions(for: item, hub: hub, center: center, route: $route) }
            )
        )
        .sheet(item: $route) { route in
            PendingSheetHost(route: route, close: { self.route = nil })
        }
        .task {
            await home.load()
            scope.homeShown()
        }
    }
}
