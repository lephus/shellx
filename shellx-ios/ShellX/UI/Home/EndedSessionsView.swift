import ShellXAppCore
import SwiftUI

/// The "Ended" page: the agents that ended in the last 12 hours, newest end first, from every Mac that
/// can be reached. A session leaves the page 12 hours after it ended, also while the page is open.
struct EndedSessionsView: View {
    let hub: MachineHub

    var body: some View {
        // Read here, not in the closure: the hub is observed whatever SwiftUI does with the closure.
        let sessions = hub.reachableSessions
        let showsMachineNames = hub.machines.count > 1
        TimelineView(.periodic(from: .now, by: 30)) { context in
            SessionListScreen(
                title: String(localized: "ended.title"), header: nil,
                items: HomeFocus.make(sessions: sessions, pending: [], finished: [:], now: context.date).ended,
                kind: .ended, now: context.date, showsMachineName: showsMachineNames,
                empty: LocalizedStringResource("ended.empty"))
        }
    }
}
