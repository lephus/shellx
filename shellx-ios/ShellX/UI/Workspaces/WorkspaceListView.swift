import ShellXAppCore
import SwiftUI

/// The app's home, "ShellX": `WorkspaceListScreen` fed by the signed-in scope. The hub gives each
/// Mac's workspaces and the sessions of the reachable Macs (sorted by `HomeFocus` every 30 seconds, so
/// "just finished" and "ended" age out with the screen open), the decision center what waits for the
/// user; the actions push screens through `open` and run the workspace commands (`WorkspaceListActions`).
///
/// It also registers where a session opens (`SessionRef`): the home's agent cards push them, and so
/// do the session lists over it.
struct WorkspaceListView: View {
    let scope: SignedInScope
    /// Pushes a screen over the list.
    let open: (HomeRoute) -> Void

    @State private var alert: WorkspaceAlert?
    @State private var creating = false

    var body: some View {
        let hub = scope.hub
        // Read here, not in the closure: the hub is observed whatever SwiftUI does with the closure.
        let pending = scope.decisions.visibleItems(hub.pendingItems)
        let groups = Self.groups(hub)
        let sessions = hub.reachableSessions
        let finishTimes = hub.finishTimes
        let dismissed = scope.endedDismissals.dismissals
        let showsMachineNames = hub.machines.count > 1
        let closableAgents = Self.closableAgents(hub)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            WorkspaceListScreen(
                groups: groups,
                focus: HomeFocus.make(
                    sessions: sessions, pending: pending, finished: finishTimes, dismissed: dismissed, now: context.date),
                pending: pending,
                creating: creating,
                notice: scope.listNotice.current,
                now: context.date,
                showsMachineNames: showsMachineNames,
                closableAgents: closableAgents,
                actions: WorkspaceListActions.make(
                    scope: scope, open: open, alert: { alert = $0 },
                    creating: Binding(get: { creating }, set: { creating = $0 })),
                alert: $alert
            )
        }
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

    /// The agents whose cards swipe to Close: the ones `WorkspaceListActions.canClose` offers, on a Mac
    /// online now. Like a workspace card's Rename and Close, none for a Mac that is away.
    static func closableAgents(_ hub: MachineHub) -> Set<SessionRef> {
        Set(hub.reachableSessions.filter { $0.online && WorkspaceListActions.canClose($0, hub: hub) }.map(\.ref))
    }
}

/// What the list's controls do, wired to the signed-in scope. Built outside the view body, so a test
/// can run each action and see the hub call it makes and what the list does with the answer:
/// - the toolbar, a Mac's header, a Mac's last row and the "Ended" fold push `HomeRoute`s through `open`;
/// - a workspace card opens its workspace and marks it seen (its agents leave "Just finished");
/// - ＋, rename and close run the hub's workspace commands, once each, and `WorkspaceFeedback` says
///   what follows: a new workspace opens, a gone one refreshes the list, anything else is an alert;
/// - a confirmed Close on an agent card closes the agent (`closeAgent(_:hub:alert:done:)`, which the
///   other screens' Close goes through too). The workspace screen closes any tab through
///   `closeTab(machineID:workspaceId:terminalId:hub:alert:done:)`.
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
            closeAgent: { ref in closeAgent(ref, hub: hub, alert: alert, done: done) },
            openPending: { open(.pending) },
            openSettings: { open(.settings) },
            openMachines: { open(.machines) },
            openOtherSessions: { open(.otherSessions(machineID: $0)) },
            openEnded: { open(.ended) },
            refresh: { await hub.refreshWorkspaces() })
    }
}

// MARK: - Closing an agent

extension WorkspaceListActions {
    /// The agents whose close is on its way to their Mac. Every Close goes through `closeAgent` (the home's
    /// cards, the agent screen's `•••`), so a second tap, or a swipe while a menu's close waits, sends
    /// nothing until the Mac answered the first.
    private static var closingAgents: Set<SessionRef> = []

    /// An agent the phone may offer to close, the one rule for every Close Agent (the home's swipe through
    /// `WorkspaceListView.closableAgents`, the agent screen's `•••`): its session has not ended (the terminal
    /// of an agent that exited runs the user's shell), a tab of its Mac's listed workspaces names it
    /// (`MachineHub.hasListedTerminal(_:)`: `agent.close` finds no other, so an agent outside workspaces has
    /// no Close), and its Mac listed `agent_close`. A menu that offers it is off while the Mac is not online;
    /// a card's swipe shows only then.
    static func canClose(_ session: MachineSession, hub: MachineHub) -> Bool {
        session.session.state != .ended && hub.supportsAgentClose(session.machineID)
            && hub.hasListedTerminal(session.ref)
    }

    /// Closes the agent of `ref` on its Mac once the user confirmed, unless a close of it waits for the Mac
    /// already. `WorkspaceFeedback` says what follows: nothing when it worked (the session moves to Ended by
    /// the Mac's push), else an alert through `alert`. `done` gets the task, so a caller (a test) can wait
    /// for it.
    static func closeAgent(
        _ ref: SessionRef, hub: MachineHub, alert: @escaping (WorkspaceAlert) -> Void,
        done: @escaping (Task<WorkspaceFeedback, Never>) -> Void = { _ in }
    ) {
        guard closingAgents.insert(ref).inserted else { return }
        done(
            Task {
                let result = await hub.closeAgent(ref)
                closingAgents.remove(ref)
                let feedback = WorkspaceFeedback.of(result, for: .closeAgent, machineID: ref.machineID)
                if case let .alert(kind) = feedback { alert(kind) }
                return feedback
            })
    }
}

// MARK: - Closing a tab

extension WorkspaceListActions {
    /// A tab whose close is on its way: its Mac and its terminal id.
    private struct ClosingTab: Hashable {
        let machineID: String
        let terminalId: String
    }

    /// The tabs whose close is on its way to their Mac. The workspace screen's `•••` and a chip's long-press
    /// both go through `closeTab`, so a second Close Tab on the same tab, from either, sends nothing until
    /// the Mac answered the first.
    private static var closingTabs: Set<ClosingTab> = []

    /// The phone may offer to close this Mac's tabs, agent or shell: it listed `terminal_close` when it was last
    /// online. The workspace screen's `•••` that offers it is off while the Mac is not online, and a chip's
    /// long-press offers it only then.
    static func canCloseTab(machineID: String, hub: MachineHub) -> Bool {
        hub.supportsTerminalClose(machineID)
    }

    /// Closes the tab `terminalId` of the workspace `workspaceId` on the Mac `machineID` once the user
    /// confirmed, unless a close of it waits for the Mac already. `WorkspaceFeedback` says what follows:
    /// nothing when it worked (the tab, or its workspace when it was the last tab, leaves by the Mac's push),
    /// else an alert through `alert`. `done` gets the task, so a caller (a test) can wait for it.
    static func closeTab(
        machineID: String, workspaceId: String, terminalId: String, hub: MachineHub,
        alert: @escaping (WorkspaceAlert) -> Void, done: @escaping (Task<WorkspaceFeedback, Never>) -> Void = { _ in }
    ) {
        let tab = ClosingTab(machineID: machineID, terminalId: terminalId)
        guard closingTabs.insert(tab).inserted else { return }
        done(
            Task {
                let result = await hub.closeTerminal(machineID, workspaceId: workspaceId, terminalId: terminalId)
                closingTabs.remove(tab)
                let feedback = WorkspaceFeedback.of(result, for: .closeTab, machineID: machineID)
                if case let .alert(kind) = feedback { alert(kind) }
                return feedback
            })
    }
}
