import ShellXAppCore
import SwiftUI

/// "Needs you · N": every Mac's pending requests as cards, in a `List`, fed by the hub through the
/// decision center (a card goes as soon as its decision is taken). It only reads the center: the
/// list's owner calls `DecisionCenter.sync(_:)` when the hub's items change. Opening a card's sheet
/// sets `route`; the owner presents it, so the sheet outlives a card that goes meanwhile.
struct PendingCardsSection: View {
    let hub: MachineHub
    let center: DecisionCenter
    @Binding var route: PendingRoute?

    var body: some View {
        let items = center.visibleItems(hub.pendingItems)
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    PendingCardView(
                        item: item, status: center.status[item.id], showsMachineName: hub.machines.count > 1,
                        actions: actions(for: item)
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text(LocalizedStringResource("pending.section.title \(items.count)"))
            }
        }
    }

    private func actions(for item: MachinePendingItem) -> PendingCardView.Actions {
        let key = item.id
        let center = self.center
        return PendingCardView.Actions(
            decide: { decision in Task { await center.send(decision, for: key) } },
            openSheet: { open(item) },
            showMore: { open(item) },
            retry: { Task { await center.retry(key) } })
    }

    private func open(_ item: MachinePendingItem) {
        let model = PendingSheetModel(key: item.id, hub: hub, center: center)
        // Gone between the tap and now: there is nothing left to show.
        guard model.opened != nil else { return }
        route = PendingRoute(kind: PendingRoute.kind(for: item.item), model: model)
    }
}
