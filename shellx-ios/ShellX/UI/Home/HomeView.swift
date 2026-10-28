import ShellXAppCore
import SwiftUI

/// The main screen, "ShellX" (plan decision D7), fed by the signed-in scope: the "Needs you" bar from
/// the decision center (its owner, `SignedInView`, keeps it synced with the hub), the agent chips
/// and the conversation from the home model, and the composer that sends through it. An agent chip
/// or a "done" note opens that session's `AgentView`.
struct HomeView: View {
    let scope: SignedInScope
    /// Pushes a screen over the home.
    let open: (HomeRoute) -> Void

    @State private var draft = ""

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
            showsMachineName: hub.machines.count > 1,
            rows: { home.statusRows },
            isLoaded: home.isLoaded,
            entries: home.entries,
            // While a message is under way, the session the chip showed when it began.
            target: home.messageTarget,
            pickedTarget: picked,
            sessions: sessions,
            draft: $draft,
            actions: HomeActions.make(scope: scope, open: open)
        )
        // The agent rows and the "done" notes push a session's screen.
        .navigationDestination(for: SessionRef.self) { ref in
            AgentView(scope: scope, ref: ref, open: open)
        }
        .task {
            await home.load()
            scope.homeShown()
        }
    }
}
