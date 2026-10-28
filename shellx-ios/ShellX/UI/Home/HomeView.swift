import ShellXAppCore
import SwiftUI

/// The main screen, "ShellX" (plan decision D7), fed by the signed-in scope: the "Needs you" bar from
/// the decision center (its owner, `SignedInView`, keeps it synced with the hub), the agent chips
/// and the conversation from the home model, and the composer that sends through it. An agent chip
/// or a "done" note opens that session's `AgentView`.
///
/// The composer offers attachments when the Mac of the session it sends to takes them
/// (`MachineHub.acceptsAttachments`), and keeps offering them while some wait in it, so none is
/// ever hidden. A message with attachments stays in the composer, locked, until the Mac answers:
/// it is cleared once taken and left to send again otherwise (`HomeSubmitResult.keepsDraft`).
struct HomeView: View {
    let scope: SignedInScope
    /// Pushes a screen over the home.
    let open: (HomeRoute) -> Void

    @State private var draft = ""
    @State private var attachments: [OutgoingAttachment] = []
    /// A message with attachments is on its way.
    @State private var sendingAttachments = false

    var body: some View {
        let hub = scope.hub
        let center = scope.decisions
        let home = scope.home
        let sessions = hub.liveSessions
        let defaultMachine = hub.machines.first { $0.id == hub.defaultMachineID }
        let picked = home.target.flatMap { target in sessions.contains { $0.ref == target } ? target : nil }
        let target = home.messageTarget
        let offersAttachments = target.map { hub.acceptsAttachments($0.machineID) } ?? false
        HomeScreen(
            machine: defaultMachine.map { (name: $0.name, state: $0.state) },
            pending: center.visibleItems(hub.pendingItems),
            showsMachineName: hub.machines.count > 1,
            rows: { home.statusRows },
            isLoaded: home.isLoaded,
            entries: home.entries,
            // While a message is under way, the session the chip showed when it began.
            target: target,
            pickedTarget: picked,
            sessions: sessions,
            draft: $draft,
            attachments: offersAttachments || !attachments.isEmpty ? $attachments : nil,
            sending: sendingAttachments ? (home.uploadProgress ?? 0) : nil,
            actions: HomeActions.make(scope: scope, open: open, sent: followSend)
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

    /// A message with attachments was handed to the home model with the composer still holding
    /// it: locks the composer until the answer, then clears it unless it is to be sent again. A
    /// text-only message already left the field.
    private func followSend(_ task: Task<HomeSubmitResult, Never>) {
        guard !attachments.isEmpty else { return }
        sendingAttachments = true
        Task {
            let result = await task.value
            sendingAttachments = false
            guard !result.keepsDraft else { return }
            draft = ""
            attachments = []
        }
    }
}
