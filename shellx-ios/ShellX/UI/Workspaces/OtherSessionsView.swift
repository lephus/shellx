import ShellXAppCore
import SwiftUI

/// "Agents outside workspaces" of one Mac, from the workspace list's last row: the live sessions no
/// terminal of the Mac's workspaces names (run over SSH, in a workspace since closed). Ended sessions
/// are on the Ended page, and the ones removed from this phone are on no list. A tap opens that session's
/// `AgentView`. A card offers no Close: `agent.close` reaches only an agent whose terminal the Mac lists in a
/// workspace, and none of these has one. A session an agent screen saw gone from its Mac this run swipes to
/// "Remove from This Phone" (`GoneRemovalStore`).
struct OtherSessionsView: View {
    let hub: MachineHub
    let removals: GoneRemovalStore
    let machineID: String

    var body: some View {
        let name = hub.machines.first { $0.id == machineID }?.name ?? ""
        let sessions = Self.sessions(hub: hub, machineID: machineID, removed: removals.removals)
        let removable = removals.removable(sessions)
        let names = SessionName.distinct(sessions)
        // Read here, not in the closure: the hub is observed whatever SwiftUI does with the closure.
        let finishTimes = hub.finishTimes[machineID] ?? [:]
        let items = sessions.map {
            FocusItem(session: $0, name: names[$0.ref] ?? $0.session.sessionId, finishedAt: finishTimes[$0.session.sessionId])
        }
        TimelineView(.periodic(from: .now, by: 30)) { context in
            SessionListScreen(
                title: String(localized: "workspaces.other.title"), header: name, items: items,
                kind: { Self.kind(of: $0.session.session, finishedAt: $0.finishedAt, now: context.date) },
                now: context.date, showsMachineName: false, empty: LocalizedStringResource("workspaces.other.empty"),
                removableGone: removable,
                removeGone: { item in
                    withAnimation(.easeInOut(duration: 0.2)) { removals.remove(item.session) }
                })
        }
    }

    /// The Mac's sessions this page lists, and the home's "Agents outside workspaces · N" counts:
    /// `MachineHub.otherSessions(machineID:)` without the ones removed from this phone (`GoneRemovals.shown`).
    static func sessions(hub: MachineHub, machineID: String, removed: GoneRemovals) -> [MachineSession] {
        removed.shown(hub.otherSessions(machineID: machineID))
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
