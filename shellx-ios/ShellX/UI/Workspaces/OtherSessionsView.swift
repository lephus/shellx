import ShellXAppCore
import SwiftUI

/// "Agents outside workspaces" of one Mac, from the workspace list's last row: the live sessions no
/// terminal of the Mac's workspaces names (run over SSH, in a workspace since closed). Ended sessions
/// are on the Ended page. A tap opens that session's `AgentView`; swiping a card to the left offers Close
/// while the Mac closes agents for the phone (`WorkspaceListView.closableMachines`), and an alert says why
/// a close did not work.
struct OtherSessionsView: View {
    let hub: MachineHub
    let machineID: String

    @State private var alert: WorkspaceAlert?

    var body: some View {
        let name = hub.machines.first { $0.id == machineID }?.name ?? ""
        let sessions = hub.otherSessions(machineID: machineID)
        let names = SessionName.distinct(sessions)
        // Read here, not in the closure: the hub is observed whatever SwiftUI does with the closure.
        let finishTimes = hub.finishTimes[machineID] ?? [:]
        let items = sessions.map {
            FocusItem(session: $0, name: names[$0.ref] ?? $0.session.sessionId, finishedAt: finishTimes[$0.session.sessionId])
        }
        let closable = WorkspaceListView.closableMachines(hub).contains(machineID)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            SessionListScreen(
                title: String(localized: "workspaces.other.title"), header: name, items: items,
                kind: { Self.kind(of: $0.session.session, finishedAt: $0.finishedAt, now: context.date) },
                now: context.date, showsMachineName: false, empty: LocalizedStringResource("workspaces.other.empty"),
                close: closable
                    ? { item in WorkspaceListActions.closeAgent(item.id, hub: hub, alert: { alert = $0 }) } : nil)
        }
        .workspaceAlert($alert)
    }

    /// The group a session is drawn in: by its state; a finished one as "done" for `HomeFocus.justDoneFor`
    /// after it finished (measured from `finishedAt` to `now`), then as idle. An ended session is "ended".
    static func kind(of session: AgentSession, finishedAt: Date?, now: Date) -> FocusRowView.Kind {
        switch session.state {
        case .needsInput: .needsYou
        case .working: .running
        case .idle:
            if let finishedAt, max(0, now.timeIntervalSince(finishedAt)) < HomeFocus.justDoneFor { .justDone } else { .idle }
        case .ended, .other: .ended
        }
    }
}
