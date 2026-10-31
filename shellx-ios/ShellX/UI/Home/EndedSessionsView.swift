import ShellXAppCore
import SwiftUI

/// The "Ended" page: the agents that ended in the last 12 hours, newest end first, from every Mac that
/// can be reached. A session leaves the page 12 hours after it ended, also while the page is open, or
/// when the user taps the trash on its card (or swipes it): that only hides it on this phone, until it
/// ends again (`EndedDismissals`). A session gone from its Mac that the user removed from this phone is not
/// on it either (`GoneRemovals`).
struct EndedSessionsView: View {
    let hub: MachineHub
    let dismissals: EndedDismissalStore
    let removals: GoneRemovalStore

    var body: some View {
        // Read here, not in the closure: the hub is observed whatever SwiftUI does with the closure.
        let sessions = hub.reachableSessions
        let showsMachineNames = hub.machines.count > 1
        let dismissed = dismissals.dismissals
        let removed = removals.removals
        TimelineView(.periodic(from: .now, by: 30)) { context in
            SessionListScreen(
                title: String(localized: "ended.title"), header: nil,
                items: HomeFocus.make(
                    sessions: sessions, pending: [], finished: [:], dismissed: dismissed, removed: removed,
                    now: context.date
                ).ended,
                kind: .ended, now: context.date, showsMachineName: showsMachineNames,
                empty: LocalizedStringResource("ended.empty"),
                remove: { item in
                    withAnimation(.easeInOut(duration: 0.2)) { dismissals.dismiss(item.session) }
                })
        }
    }
}
