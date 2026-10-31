import ShellXAppCore
import SwiftUI

/// One workspace of a Mac, pushed from the workspace list: `WorkspaceScreen` fed by
/// `WorkspaceScreenModel` and the hub. A chip that runs an agent shows the existing agent screen as its
/// pane (`AgentView`, embedded); the commands in `•••` are the hub's (`WorkspaceScreenActions`).
///
/// When the pane shown is closed on the Mac, the next chip shows and a short line says why
/// (`paneClosedNotice`). It leaves on its own when the workspace it showed is closed on the Mac: it
/// pops, and the list says so in a short line. When the Mac is removed from this iPhone it pops without
/// a word; a list emptied for any other reason (the Mac offline, no longer reachable) keeps the last
/// chips. A workspace the Mac has not listed yet (a create answers before the list that holds it) shows
/// a spinner; one that does not come says it is not found.
struct WorkspaceView: View {
    let scope: SignedInScope
    let ref: WorkspaceRef
    /// Pushes a screen (an agent's "Needs you" bar opens this workspace's pending cards).
    let open: (HomeRoute) -> Void

    @State private var model: WorkspaceScreenModel
    @State private var alert: WorkspaceAlert?
    /// The user confirmed closing the workspace here: its leaving needs no word of explanation.
    @State private var closedHere = false
    /// The line over the pages, for `AgentView.noticeDuration`.
    @State private var notice: AgentScreen.Notice?
    @Environment(\.dismiss) private var dismiss
    @Environment(VoiceService.self) private var voiceService: VoiceService?

    init(scope: SignedInScope, ref: WorkspaceRef, open: @escaping (HomeRoute) -> Void) {
        self.scope = scope
        self.ref = ref
        self.open = open
        _model = State(initialValue: WorkspaceScreenModel(ref: ref, hub: scope.hub))
    }

    var body: some View {
        let model = self.model
        Group {
            switch model.phase {
            case .showing:
                WorkspaceScreen(
                    title: model.workspace?.title ?? "", branch: model.workspace?.branch, panes: model.panes,
                    selected: model.selectedTerminalId, canControl: model.canControl,
                    closableAgent: Self.closableAgent(model, hub: scope.hub),
                    pagingLocked: voiceService?.isListening ?? false, notice: notice,
                    actions: WorkspaceScreenActions.make(
                        scope: scope, model: model,
                        alert: {
                            closedHere = false
                            alert = $0
                        },
                        closing: { closedHere = true }),
                    alert: $alert,
                    agent: { session in
                        // Another session in the same terminal is another chat, not this one's model.
                        AgentView(scope: scope, ref: session.ref, embedded: true, open: open)
                            .id(session.ref)
                    })
            case .waiting:
                WorkspaceWaitingView()
            case .notFound:
                WorkspaceMissingView(back: { dismiss() })
            case .dismissed, .machineRemoved:
                Color.appBackground.ignoresSafeArea()
            }
        }
        .task { await model.run() }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .dismissed: leave()
            case .machineRemoved: dismiss()
            case .waiting, .showing, .notFound: break
            }
        }
        .onChange(of: model.shownPaneClosed) { _, _ in
            let text = Self.paneClosedNotice
            notice = AgentScreen.Notice(text: text)
            AccessibilityNotification.Announcement(text).post()
        }
        .task(id: notice?.id) {
            guard notice != nil else { return }
            do { try await Task.sleep(for: AgentView.noticeDuration) } catch { return }
            notice = nil
        }
        // Whatever finished while the user was here, the user saw.
        .onDisappear { scope.hub.markSeen(ref) }
    }

    /// The workspace is gone: back to the list, with a line saying why unless the user closed it here.
    private func leave() {
        if let text = Self.leavingNotice(closedHere: closedHere) {
            scope.listNotice.show(text)
            AccessibilityNotification.Announcement(text).post()
        }
        dismiss()
    }

    /// The chip shown, when it runs an agent the phone may close (`WorkspaceListActions.canClose`): one
    /// whose session has not ended, on a Mac that lists `agent_close`. Nil for a shell.
    static func closableAgent(_ model: WorkspaceScreenModel, hub: MachineHub) -> WorkspacePane? {
        let panes = model.panes
        let shown = model.selectedTerminalId ?? panes.first?.id
        guard let pane = panes.first(where: { $0.id == shown }), let session = pane.session,
            WorkspaceListActions.canClose(session, hub: hub)
        else { return nil }
        return pane
    }

    /// What the screen says when the pane shown was closed on the Mac and the next chip shows.
    static var paneClosedNotice: String { String(localized: "workspace.paneClosedOnMac") }

    /// What the list says after this screen left because its workspace is gone; nothing when the user
    /// closed the workspace here.
    static func leavingNotice(closedHere: Bool) -> String? {
        closedHere ? nil : String(localized: "workspace.closedOnMac")
    }
}

/// The workspace screen's controls wired to the hub. Built outside the view body, so a test can run each
/// action and see the hub call it makes and what the screen does with the answer (`WorkspaceFeedback`,
/// the words the list says too): a workspace that is gone refreshes the list, anything that did not work
/// is an alert, and an answer of "done" shows nothing (the Mac's push renames the workspace, or removes
/// it and the screen leaves).
extension WorkspaceScreenActions {
    /// `alert` gets what to tell the user; `closing` is called when the user's close goes out. `done` gets
    /// the task of each command, so a caller (a test) can wait for it.
    @MainActor static func make(
        scope: SignedInScope, model: WorkspaceScreenModel, alert: @escaping (WorkspaceAlert) -> Void,
        closing: @escaping () -> Void = {}, done: @escaping (Task<WorkspaceFeedback, Never>) -> Void = { _ in }
    ) -> WorkspaceScreenActions {
        let hub = scope.hub
        let ref = model.ref
        func run(_ command: WorkspaceCommand, _ call: @escaping () async -> WorkspaceCommandResult) {
            done(
                Task {
                    let feedback = WorkspaceFeedback.of(await call(), for: command, machineID: ref.machineID)
                    switch feedback {
                    case .nothing, .open: break
                    case .refresh: await hub.refreshWorkspaces(machineID: ref.machineID)
                    case let .alert(kind): alert(kind)
                    }
                    return feedback
                })
        }
        return WorkspaceScreenActions(
            select: { model.select($0) },
            rename: { title in
                run(.rename) { await hub.renameWorkspace(ref, title: title) }
            },
            close: {
                closing()
                run(.close) { await hub.closeWorkspace(ref) }
            },
            closeAgent: { session in
                // Not `closing`: the workspace stays unless the agent's tab was its last, and then the list
                // says it closed on the Mac.
                WorkspaceListActions.closeAgent(session, hub: hub, alert: alert, done: done)
            })
    }
}
