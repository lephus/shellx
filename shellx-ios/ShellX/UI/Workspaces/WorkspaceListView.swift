import ShellXAppCore
import SwiftUI

/// The app's home, "Workspace": `WorkspaceListScreen` fed by the signed-in scope. The hub gives each
/// Mac's workspaces (rows with their state), the decision center what waits for the user; the actions
/// push screens through `open` and run the workspace commands (`WorkspaceListActions`).
///
/// It also registers where a session opens (`SessionRef`): the "Other agent sessions" list pushes
/// them, and so did the screens before.
struct WorkspaceListView: View {
    let scope: SignedInScope
    /// Pushes a screen over the list.
    let open: (HomeRoute) -> Void

    @State private var alert: WorkspaceAlert?
    @State private var creating = false

    var body: some View {
        let hub = scope.hub
        WorkspaceListScreen(
            groups: Self.groups(hub),
            pending: scope.decisions.visibleItems(hub.pendingItems),
            creating: creating,
            notice: scope.listNotice.current,
            actions: WorkspaceListActions.make(
                scope: scope, open: open, alert: { alert = $0 },
                creating: Binding(get: { creating }, set: { creating = $0 })),
            alert: $alert
        )
        .navigationDestination(for: SessionRef.self) { ref in
            AgentView(scope: scope, ref: ref, open: open)
        }
        .task { scope.homeShown() }
        .onChange(of: hub.defaultMachineListedWorkspaces, initial: true) { _, listed in
            if listed { scope.workspacesListed() }
        }
        .task(id: scope.listNotice.current?.id) {
            guard let id = scope.listNotice.current?.id else { return }
            do { try await Task.sleep(for: AgentView.noticeDuration) } catch { return }
            scope.listNotice.clear(id)
        }
    }

    /// The hub's Macs as groups, the default Mac first and the others in the order they were paired.
    static func groups(_ hub: MachineHub) -> [WorkspaceGroup] {
        let defaultID = hub.defaultMachineID
        let models = hub.machines.filter { $0.id == defaultID } + hub.machines.filter { $0.id != defaultID }
        return models.map { model in
            WorkspaceGroup(
                id: model.id, name: model.name, state: model.state, isDefault: model.id == defaultID,
                rows: hub.workspaceRows(machineID: model.id), allowsControl: hub.supportsWorkspaceControl(model.id),
                // A Mac not online yet has not said what it lists: no "update ShellX" before it has.
                listsWorkspaces: model.workspacesSupported || model.state != .online,
                otherSessionCount: hub.otherSessions(machineID: model.id).count)
        }
    }
}

/// What the list's controls do, wired to the signed-in scope. Built outside the view body, so a test
/// can run each action and see the hub call it makes and what the list does with the answer:
/// - the toolbar, the "Needs you" bar, a Mac's header and the last row push `HomeRoute`s through `open`;
/// - a card opens its workspace and marks it seen (its "done" label goes);
/// - ＋, rename and close run the hub's workspace commands, once each, and `WorkspaceFeedback` says
///   what follows: a new workspace opens, a gone one refreshes the list, anything else is an alert.
@MainActor
enum WorkspaceListActions {
    /// `done` gets the task of each command, so a caller (a test) can wait for it. `creating` is set
    /// from ＋ until the Mac answered, so a second tap does not make a second workspace.
    static func make(
        scope: SignedInScope, open: @escaping (HomeRoute) -> Void, alert: @escaping (WorkspaceAlert) -> Void,
        creating: Binding<Bool>, done: @escaping (Task<WorkspaceFeedback, Never>) -> Void = { _ in }
    ) -> WorkspaceListScreen.Actions {
        let hub = scope.hub
        func run(
            _ command: WorkspaceCommand, machineID: String, _ call: @escaping () async -> WorkspaceCommandResult
        ) {
            done(
                Task {
                    let feedback = WorkspaceFeedback.of(await call(), for: command, machineID: machineID)
                    switch feedback {
                    case .nothing: break
                    case let .open(ref): open(.workspace(ref))
                    case .refresh: await hub.refreshWorkspaces(machineID: machineID)
                    case let .alert(kind): alert(kind)
                    }
                    return feedback
                })
        }
        return WorkspaceListScreen.Actions(
            openWorkspace: { ref in
                hub.markSeen(ref)
                open(.workspace(ref))
            },
            create: { machineID in
                guard !creating.wrappedValue else { return }
                creating.wrappedValue = true
                run(.create, machineID: machineID) {
                    defer { creating.wrappedValue = false }
                    return await hub.createWorkspace(machineID: machineID)
                }
            },
            rename: { ref, title in
                run(.rename, machineID: ref.machineID) { await hub.renameWorkspace(ref, title: title) }
            },
            close: { ref in
                run(.close, machineID: ref.machineID) { await hub.closeWorkspace(ref) }
            },
            openPending: { open(.pending) },
            openSettings: { open(.settings) },
            openMachines: { open(.machines) },
            openOtherSessions: { open(.otherSessions(machineID: $0)) },
            refresh: { await hub.refreshWorkspaces() })
    }
}
