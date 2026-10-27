import ShellXAppCore
import SwiftUI

/// "Needs You": every pending card, from the home's "See all (N)". It only reads the decision
/// center; `SignedInView` keeps it synced with the hub.
struct PendingListView: View {
    let hub: MachineHub
    let center: DecisionCenter

    @State private var route: PendingRoute?

    var body: some View {
        List {
            PendingCardsSection(hub: hub, center: center, route: $route)
        }
        .overlay {
            if center.visibleItems(hub.pendingItems).isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "pending.list.empty"), systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle(String(localized: "pending.list.title"))
        .sheet(item: $route) { route in
            PendingSheetHost(route: route, close: { self.route = nil })
        }
    }
}
