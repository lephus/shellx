import ShellXAppCore
import SwiftUI

/// One workspace of a Mac, pushed from the workspace list: `WorkspaceScreen` fed by
/// `WorkspaceScreenModel` and the hub. A chip that runs an agent shows the existing agent screen as its
/// pane (`AgentView`, embedded); a shell chip, or an agent chip shown as its terminal, shows the Mac's terminal
/// (`TerminalPane`). One `TerminalViewModel` serves every page and shows the terminal of the chip shown
/// (`WorkspaceScreenModel.terminalShown`), never a neighbour the pager keeps alive; it closes the view while the app
/// is in the background and opens it again on return. The commands in `•••` and ＋ are the hub's
/// (`WorkspaceScreenActions`).
///
/// When the pane shown is closed on the Mac, the next chip shows and a short line says why
/// (`paneClosedNotice`). It leaves on its own when the workspace it showed is closed on the Mac: it
/// pops, and the list says so in a short line. A tab, or a workspace, the user closed from this screen
/// goes the same way without either line. When the Mac is removed from this iPhone it pops without
/// a word; a list emptied for any other reason (the Mac offline, no longer reachable) keeps the last
/// chips. A workspace the Mac has not listed yet (a create answers before the list that holds it) shows
/// a spinner; one that does not come says it is not found.
struct WorkspaceView: View {
    let scope: SignedInScope
    let ref: WorkspaceRef
    /// Pushes a screen (an agent's "Needs you" bar opens this workspace's pending cards).
    let open: (HomeRoute) -> Void

    @State private var model: WorkspaceScreenModel
    /// The terminal shown, for every terminal page of this screen.
    @State private var terminal: TerminalViewModel
    @State private var alert: WorkspaceAlert?
    /// The user confirmed closing the workspace here: its leaving needs no word of explanation.
    @State private var closedHere = false
    /// The line over the pages, for `AgentView.noticeDuration`.
    @State private var notice: AgentScreen.Notice?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(VoiceService.self) private var voiceService: VoiceService?

    init(scope: SignedInScope, ref: WorkspaceRef, open: @escaping (HomeRoute) -> Void) {
        self.scope = scope
        self.ref = ref
        self.open = open
        _model = State(initialValue: WorkspaceScreenModel(ref: ref, hub: scope.hub))
        _terminal = State(initialValue: TerminalViewModel(machineID: ref.machineID, link: scope.hub))
    }

    var body: some View {
        let model = self.model
        let terminal = self.terminal
        let hub = scope.hub
        Group {
            switch model.phase {
            case .showing:
                WorkspaceScreen(
                    title: model.workspace?.title ?? "", branch: model.workspace?.branch, panes: model.panes,
                    selected: model.selectedTerminalId, canControl: model.canControl,
                    canCloseTab: WorkspaceListActions.canCloseTab(machineID: ref.machineID, hub: hub),
                    canCreateTerminal: hub.supportsTerminalCreate(ref.machineID),
                    canViewTerminals: hub.supportsTerminalView(ref.machineID), shownAsTerminal: model.shownAsTerminal,
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
                    },
                    shell: { pane in
                        // Typing into a page settles the screen on it: an agent that starts asking does not pull
                        // the keyboard away mid-command.
                        TerminalPane(
                            model: terminal, terminalId: pane.id, title: PaneChips.label(for: pane),
                            engaged: { model.settle() })
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
        .task { await terminal.run() }
        .onChange(of: model.terminalShown, initial: true) { _, id in terminal.show(id) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                terminal.suspend()
            } else if phase == .active {
                terminal.resume()
            }
        }
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

    /// The workspace is gone: back to the list, with a line saying why unless the user closed it, or its
    /// last tab, here.
    private func leave() {
        if let text = Self.leavingNotice(closedHere: closedHere || model.lastTabClosedHere) {
            scope.listNotice.show(text)
            AccessibilityNotification.Announcement(text).post()
        }
        dismiss()
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
/// is an alert, and an answer of "done" shows nothing (the Mac's push renames the workspace, removes a
/// tab and the next chip shows, adds the tab ＋ made and its chip shows, or removes the workspace and the
/// screen leaves).
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
            closeTab: { terminalId in
                // Not `closing`: the workspace stays unless the tab was its last. The model knows the user
                // closed it here, so neither the tab's leaving nor the workspace's says "closed on the Mac".
                model.closesHere(terminalId)
                WorkspaceListActions.closeTab(
                    machineID: ref.machineID, workspaceId: ref.workspaceId, terminalId: terminalId, hub: hub,
                    alert: { kind in
                        model.keeps(terminalId)
                        alert(kind)
                    },
                    done: done)
            },
            createTerminal: {
                run(.createTerminal) {
                    let answer = await hub.createTerminal(ref)
                    // Shown as soon as the Mac's list has it; the Mac's own selected tab stays.
                    if let id = answer.terminalId { model.expect(id) }
                    return answer.result
                }
            },
            showAsTerminal: { model.showAsTerminal($0, $1) })
    }
}
