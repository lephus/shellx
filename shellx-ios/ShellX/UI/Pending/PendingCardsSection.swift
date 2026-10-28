import ShellXAppCore
import SwiftUI

/// "Needs you · N": pending requests as cards, in a `List`. The owner passes the items the decision
/// center shows (a card goes as soon as its decision is taken); the owner also calls
/// `DecisionCenter.sync(_:)` when the hub's items change. Opening a card's sheet sets `route`; the
/// owner presents it, so the sheet outlives a card that goes meanwhile.
struct PendingCardsSection: View {
    let items: [MachinePendingItem]
    let hub: MachineHub
    let center: DecisionCenter
    @Binding var route: PendingRoute?

    var body: some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    PendingCardView(
                        item: item, status: center.status[item.id], showsMachineName: hub.machines.count > 1,
                        actions: Self.actions(for: item, hub: hub, center: center, route: $route)
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

    /// A card's buttons: decisions go through the center; "Answer", "Review plan" and "Show more"
    /// set `route` to the item's sheet.
    @MainActor
    static func actions(
        for item: MachinePendingItem, hub: MachineHub, center: DecisionCenter, route: Binding<PendingRoute?>
    ) -> PendingCardView.Actions {
        let key = item.id
        let open = {
            let model = PendingSheetModel(key: item.id, hub: hub, center: center)
            // Gone between the tap and now: there is nothing left to show.
            guard model.opened != nil else { return }
            route.wrappedValue = PendingRoute(kind: PendingRoute.kind(for: item.item), model: model)
        }
        return PendingCardView.Actions(
            decide: { decision in Task { await center.send(decision, for: key) } },
            openSheet: open,
            showMore: open,
            retry: { Task { await center.retry(key) } })
    }
}
