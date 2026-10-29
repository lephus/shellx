import ShellXAppCore
import SwiftUI

/// "Needs You": the pending cards, from a "Needs you" bar (the home's shows every one, an agent
/// screen's only its workspace's, through `only`). It only reads the decision center;
/// `SignedInView` keeps it synced with the hub. Once the last card is handled it says so for a
/// moment and goes back by itself.
struct PendingListView: View {
    let hub: MachineHub
    let center: DecisionCenter
    /// The requests this page shows; nil shows them all.
    var only: ((MachinePendingItem) -> Bool)?

    /// How long "Nothing needs you" shows before the page goes back.
    static let leaveDelay: Duration = .milliseconds(700)

    @State private var route: PendingRoute?
    /// A card showed here: the page goes back once there are none (never when it opened empty).
    @State private var hadItems = false
    @Environment(\.dismiss) private var dismiss

    private var items: [MachinePendingItem] {
        let all = hub.pendingItems
        return center.visibleItems(only.map { all.filter($0) } ?? all)
    }

    var body: some View {
        let items = self.items
        // Handled, and no sheet up (closing it would lose an answer being typed).
        let finished = hadItems && items.isEmpty && route == nil
        List {
            PendingCardsSection(items: items, hub: hub, center: center, route: $route)
        }
        .themedList()
        .animation(.snappy, value: items.map(\.id))
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "pending.list.empty"), systemImage: "checkmark.circle")
                }
                .transition(.opacity)
            }
        }
        .navigationTitle(String(localized: "pending.list.title"))
        .sheet(item: $route) { route in
            PendingSheetHost(route: route, close: { self.route = nil })
        }
        .onChange(of: items.isEmpty, initial: true) { _, empty in
            if !empty { hadItems = true }
        }
        .task(id: finished) {
            guard finished else { return }
            do { try await Task.sleep(for: Self.leaveDelay) } catch { return }
            dismiss()
        }
    }
}
