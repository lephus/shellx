import ShellXAppCore
import SwiftUI

/// A page of agent sessions as cards: "Agents outside workspaces" and "Ended". Built from plain values
/// so render tests can show it; the views that read the hub only adapt it. A tap pushes the session's
/// `AgentView` (`WorkspaceListView` registers `SessionRef`).
struct SessionListScreen: View {
    let title: String
    /// Over the cards, e.g. a Mac's name; none for a list that spans the Macs.
    let header: String?
    let items: [FocusItem]
    /// The group each card is drawn in.
    let kind: (FocusItem) -> FocusRowView.Kind
    let now: Date
    let showsMachineName: Bool
    /// Shown in place of the cards when there are none.
    let empty: LocalizedStringResource

    init(
        title: String, header: String?, items: [FocusItem], kind: @escaping (FocusItem) -> FocusRowView.Kind,
        now: Date, showsMachineName: Bool, empty: LocalizedStringResource
    ) {
        self.title = title
        self.header = header
        self.items = items
        self.kind = kind
        self.now = now
        self.showsMachineName = showsMachineName
        self.empty = empty
    }

    /// Every card in the same group.
    init(
        title: String, header: String?, items: [FocusItem], kind: FocusRowView.Kind, now: Date,
        showsMachineName: Bool, empty: LocalizedStringResource
    ) {
        self.init(
            title: title, header: header, items: items, kind: { _ in kind }, now: now,
            showsMachineName: showsMachineName, empty: empty)
    }

    private static let cardInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)

    var body: some View {
        List {
            if items.isEmpty {
                Text(empty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("sessionList.empty")
            } else {
                if let header {
                    Text(verbatim: header)
                        .font(.footnote.weight(.semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(items) { item in
                    NavigationLink(value: item.id) {
                        FocusRowView(item: item, kind: kind(item), now: now, showsMachineName: showsMachineName)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .accessibilityHint(Text(LocalizedStringResource("agent.open.hint")))
                    .accessibilityIdentifier("sessionList.row.\(item.session.session.sessionId)")
                    .listRowInsets(Self.cardInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .themedList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
