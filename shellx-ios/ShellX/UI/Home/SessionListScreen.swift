import ShellXAppCore
import SwiftUI

/// A page of agent sessions as cards: "Agents outside workspaces" and "Ended". Built from plain values
/// so render tests can show it; the views that read the hub only adapt it. A tap pushes the session's
/// `AgentView` (`WorkspaceListView` registers `SessionRef`).
///
/// It is laid out as the home is: a plain list with the same room around a card
/// (`WorkspaceListScreen.cardInsets`) and no gap over the first one. With `remove` each card has a trash
/// button at its right edge, and swiping the card to the left does the same. With `close` each card of a
/// live session swipes to Close, which asks first; the Ended page has none.
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
    /// Takes a card off the list; nil draws no trash.
    let remove: ((FocusItem) -> Void)?
    /// Confirmed: closes the card's agent on its Mac. Nil, or an ended session, offers no Close.
    let close: ((FocusItem) -> Void)?

    @State private var closing: FocusItem?

    init(
        title: String, header: String?, items: [FocusItem], kind: @escaping (FocusItem) -> FocusRowView.Kind,
        now: Date, showsMachineName: Bool, empty: LocalizedStringResource, remove: ((FocusItem) -> Void)? = nil,
        close: ((FocusItem) -> Void)? = nil
    ) {
        self.title = title
        self.header = header
        self.items = items
        self.kind = kind
        self.now = now
        self.showsMachineName = showsMachineName
        self.empty = empty
        self.remove = remove
        self.close = close
    }

    /// Every card in the same group.
    init(
        title: String, header: String?, items: [FocusItem], kind: FocusRowView.Kind, now: Date,
        showsMachineName: Bool, empty: LocalizedStringResource, remove: ((FocusItem) -> Void)? = nil
    ) {
        self.init(
            title: title, header: header, items: items, kind: { _ in kind }, now: now,
            showsMachineName: showsMachineName, empty: empty, remove: remove)
    }

    /// The trash button's square: a touch target of 44 points at the card's right edge, which the card's
    /// text leaves free.
    private static let removeSize: CGFloat = 44

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
                        FocusRowView(
                            item: item, kind: kind(item), now: now, showsMachineName: showsMachineName,
                            trailingInset: remove == nil ? 0 : Self.removeSize)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .accessibilityHint(Text(LocalizedStringResource("agent.open.hint")))
                    .accessibilityIdentifier("sessionList.row.\(item.session.session.sessionId)")
                    // Over the link, not in its label: a button in the label would be one element with the card.
                    .overlay(alignment: .trailing) {
                        if let remove { removeButton(for: item, remove) }
                    }
                    .listRowInsets(WorkspaceListScreen.cardInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    // A full swipe takes a card off at once; Close asks first, so it waits for a tap.
                    .swipeActions(edge: .trailing, allowsFullSwipe: remove != nil) {
                        if let remove {
                            // `.destructive`: nothing is asked, so the row may go as soon as it is swiped.
                            Button(role: .destructive) {
                                remove(item)
                            } label: {
                                Label(String(localized: "ended.remove"), systemImage: "trash")
                            }
                        }
                        if close != nil, item.session.session.state != .ended {
                            // Not `.destructive`: that role lets iOS animate the row away before the
                            // confirmation the button only opens.
                            Button {
                                closing = item
                            } label: {
                                Label(String(localized: "agent.close"), systemImage: "xmark")
                            }
                            .tint(Color("StatusError"))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        // As on the home, a title row is shorter than a list's 44-point rows; the cards keep 44.
        .environment(\.defaultMinListRowHeight, 0)
        .themedList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .agentCloseConfirmation($closing, name: \.name) { close?($0) }
    }

    /// The trash at the card's right edge. Borderless, so a tap on it is its own and the row's link
    /// stays for the rest of the card.
    private func removeButton(for item: FocusItem, _ remove: @escaping (FocusItem) -> Void) -> some View {
        Button {
            remove(item)
        } label: {
            Image(systemName: "trash")
                // `Color`, not the hierarchical `.secondary`: that one is the button's accent colour, faded.
                .foregroundStyle(Color.secondary)
                .frame(width: Self.removeSize, height: Self.removeSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(LocalizedStringResource("ended.remove.named \(item.name)")))
        .accessibilityIdentifier("sessionList.remove.\(item.session.session.sessionId)")
    }
}
