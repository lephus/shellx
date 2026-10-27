import ShellXAppCore
import SwiftUI

/// "Needs you · N" pinned above the conversation: the first two cards (one at the accessibility
/// text sizes), and "See all (N)" when there are more. No hub here: the owner passes the items the
/// decision center shows, their status and the card actions.
struct PinnedSection: View {
    let items: [MachinePendingItem]
    let status: [PendingKey: DecisionStatus]
    /// Two or more Macs are paired: each card names its Mac.
    let showsMachineName: Bool
    let actions: (MachinePendingItem) -> PendingCardView.Actions
    let seeAll: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var shown: Int { typeSize.isAccessibilitySize ? 1 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringResource("pending.section.title \(items.count)"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("AccentText"))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if items.count > shown {
                    Button(action: seeAll) {
                        Text(LocalizedStringResource("home.pending.seeAll \(items.count)"))
                            .font(.subheadline)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .tint(Color("AccentText"))
                    .accessibilityIdentifier("home.pending.seeAll")
                }
            }
            .frame(minHeight: 44)
            ForEach(items.prefix(shown)) { item in
                PendingCardView(
                    item: item, status: status[item.id], showsMachineName: showsMachineName, actions: actions(item))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.pinned")
    }
}
