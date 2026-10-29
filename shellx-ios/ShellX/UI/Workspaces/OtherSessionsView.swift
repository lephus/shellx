import ShellXAppCore
import SwiftUI

/// "Agents outside workspaces" of one Mac, from the workspace list's last row: the live sessions no
/// terminal of the Mac's workspaces names (run over SSH, in a workspace since closed). Ended sessions
/// are on the Ended page. A tap opens that session's `AgentView`.
struct OtherSessionsView: View {
    let hub: MachineHub
    let machineID: String

    var body: some View {
        let name = hub.machines.first { $0.id == machineID }?.name ?? ""
        let sessions = hub.otherSessions(machineID: machineID)
        let names = SessionName.distinct(sessions)
        let finished = hub.finishedSessionIds(machineID: machineID)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            SessionListScreen(
                title: String(localized: "workspaces.other.title"), header: name,
                items: sessions.map {
                    FocusItem(
                        session: $0, name: names[$0.ref] ?? $0.session.sessionId,
                        finishedAt: hub.finishTimes[machineID]?[$0.session.sessionId])
                },
                kind: { Self.kind(of: $0.session.session, finished: finished) },
                now: context.date, showsMachineName: false, empty: LocalizedStringResource("workspaces.other.empty"))
        }
    }

    /// The group a session is drawn in: by its state, a finished one as "done".
    static func kind(of session: AgentSession, finished: Set<String>) -> FocusRowView.Kind {
        switch session.state {
        case .needsInput: .needsYou
        case .working: .running
        case .idle where finished.contains(session.sessionId): .justDone
        case .idle, .ended, .other: .ended
        }
    }
}
