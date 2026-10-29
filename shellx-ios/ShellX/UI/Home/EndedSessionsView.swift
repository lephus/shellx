import ShellXAppCore
import SwiftUI

/// The "Ended" page: the agents that ended in the last 12 hours, newest end first, from every Mac that
/// can be reached. A session leaves the page 12 hours after it ended, also while the page is open.
struct EndedSessionsView: View {
    let hub: MachineHub

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            SessionListScreen(
                title: String(localized: "ended.title"), header: nil,
                items: HomeFocus.make(sessions: hub.reachableSessions, pending: [], finished: [:], now: context.date).ended,
                kind: .ended, now: context.date, showsMachineName: hub.machines.count > 1,
                empty: LocalizedStringResource("ended.empty"))
        }
    }
}
