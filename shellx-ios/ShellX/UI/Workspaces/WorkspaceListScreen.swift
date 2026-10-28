import ShellXAppCore
import SwiftUI

/// One Mac's part of the workspace list, copied from the hub so render tests can show any state.
struct WorkspaceGroup: Identifiable, Equatable {
    var id: String
    var name: String
    var state: MachineLinkState
    var isDefault: Bool
    var rows: [WorkspaceRow]
    /// The Mac listed the `workspace_control` feature: it takes make, rename and close.
    var allowsControl: Bool
    /// False when the Mac is online but lists no workspaces: a ShellX from before them.
    var listsWorkspaces: Bool
    /// How many sessions no workspace row accounts for (`MachineHub.otherSessions(machineID:)`).
    var otherSessionCount: Int

    /// Rows show for a Mac that is, or was a moment ago, online; any other Mac shows only why it has none.
    static func rowsShow(for state: MachineLinkState) -> Bool {
        switch state {
        case .online, .connecting, .reconnecting: true
        case .offline, .revoked, .hostKeyChanged, .needsUpdate: false
        }
    }

    var showsRows: Bool { Self.rowsShow(for: state) }
    /// Commands reach the Mac: it is online and takes them.
    var canControl: Bool { state == .online && allowsControl }

    /// What the group shows under its header.
    enum Listing: Equatable {
        /// Nothing: the Mac is out of reach, and its header says why.
        case hidden
        /// A notice in place of the cards: the Mac is online but its ShellX lists no workspaces.
        case updateMac
        /// A line saying the Mac has no workspace.
        case empty
        /// A card per workspace.
        case rows
    }

    var listing: Listing {
        guard showsRows else { return .hidden }
        if !listsWorkspaces { return .updateMac }
        if rows.isEmpty, state == .online { return .empty }
        return .rows
    }

    /// The last row, "Other agent sessions · N".
    var showsOtherSessions: Bool { showsRows && otherSessionCount > 0 }
}

/// The app's home: the workspaces of every paired Mac, grouped by Mac, from plain values so render
/// tests can show any state; `WorkspaceListView` feeds it from the hub.
///
/// - Top, pinned: the "Needs you · N" bar while something waits.
/// - Toolbar: the bell with the same count (the requests page), ＋ (make a workspace; a menu of the
///   online Macs when there are several) and Settings.
/// - One section per Mac, the default Mac first: its header (opens "Your Macs"), then a card per
///   workspace in the Mac's order, then "Other agent sessions · N" when some sessions have no card.
///   A Mac that cannot list workspaces says so in a card; an offline one shows only its header.
/// - A card opens its workspace; swipe it to the left for Rename and Close (Macs that take them).
///   Pulling the list down asks the Macs for their workspaces again.
struct WorkspaceListScreen: View {
    struct Actions {
        var openWorkspace: (WorkspaceRef) -> Void = { _ in }
        /// ＋ on the Mac with this id.
        var create: (String) -> Void = { _ in }
        /// The workspace's new name, trimmed and not empty.
        var rename: (WorkspaceRef, String) -> Void = { _, _ in }
        /// Confirmed: close the workspace and its terminals.
        var close: (WorkspaceRef) -> Void = { _ in }
        var openPending: () -> Void = {}
        var openSettings: () -> Void = {}
        var openMachines: () -> Void = {}
        var openOtherSessions: (String) -> Void = { _ in }
        /// Pull to refresh: runs until the Macs answered.
        var refresh: () async -> Void = {}
    }

    let groups: [WorkspaceGroup]
    /// What waits for the user, on every Mac.
    let pending: [MachinePendingItem]
    /// A workspace is being made: ＋ waits for the Mac's answer.
    var creating = false
    /// A short line over the bottom edge: a workspace screen that closed itself says why.
    var notice: AgentScreen.Notice?
    var actions = Actions()
    /// Why the last command did not work; the screen shows it until it is dismissed.
    @Binding var alert: WorkspaceAlert?

    @State private var renaming: WorkspaceRow?
    @State private var closing: WorkspaceRow?

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    content(of: group)
                } header: {
                    MachineGroupHeader(group: group, showsDefault: groups.count > 1, open: actions.openMachines)
                        .background(Color.appBackground)
                }
            }
        }
        .listStyle(.plain)
        .themedList()
        .refreshable { await actions.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) { needsYou }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice { NoticeCapsule(text: notice.text) }
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
        .navigationTitle(String(localized: "workspaces.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                bell
                create
                Button(action: actions.openSettings) {
                    Label(String(localized: "settings.title"), systemImage: "gearshape")
                }
                .accessibilityIdentifier("root.settings")
            }
        }
        .sheet(item: $renaming) { row in
            WorkspaceRenameSheet(
                current: row.title,
                save: { title in
                    renaming = nil
                    actions.rename(row.id, title)
                },
                cancel: { renaming = nil })
        }
        .confirmationDialog(
            closing.map { String(localized: "workspaces.close.title \($0.title)") } ?? "",
            isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
            titleVisibility: .visible, presenting: closing
        ) { row in
            Button(String(localized: "workspaces.close"), role: .destructive) { actions.close(row.id) }
        } message: { _ in
            Text(LocalizedStringResource("workspaces.close.confirm"))
        }
        .workspaceAlert($alert)
    }

    // MARK: - Top

    @ViewBuilder private var needsYou: some View {
        if !pending.isEmpty {
            NeedsYouBar(items: pending, showsMachineName: groups.count > 1, open: actions.openPending)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.appBackground)
                .overlay(alignment: .bottom) { Divider() }
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// The bell: opens the requests page, with how many wait on it beside it.
    private var bell: some View {
        Button(action: actions.openPending) {
            HStack(spacing: 4) {
                Image(systemName: "bell")
                if !pending.isEmpty {
                    Text(verbatim: pending.count > 99 ? "99+" : "\(pending.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PrimaryButtonStyle.label)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color("AccentColor"), in: Capsule())
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(
            pending.isEmpty
                ? Text(LocalizedStringResource("workspaces.bell"))
                : Text(LocalizedStringResource("pending.section.title \(pending.count)"))
        )
        .accessibilityIdentifier("workspaces.bell")
    }

    /// ＋: one online Mac that takes workspaces, a button; several, a menu to pick the Mac; none, off.
    @ViewBuilder private var create: some View {
        let targets = groups.filter(\.canControl)
        if targets.count > 1 {
            Menu {
                Section(String(localized: "workspaces.create.pickMac")) {
                    ForEach(targets) { group in
                        Button(group.name) { actions.create(group.id) }
                    }
                }
            } label: {
                Label(String(localized: "workspaces.create"), systemImage: "plus")
            }
            .disabled(creating)
            .accessibilityIdentifier("workspaces.create")
        } else {
            Button {
                if let only = targets.first { actions.create(only.id) }
            } label: {
                Label(String(localized: "workspaces.create"), systemImage: "plus")
            }
            .disabled(targets.isEmpty || creating)
            .accessibilityIdentifier("workspaces.create")
        }
    }

    // MARK: - A Mac's group

    @ViewBuilder private func content(of group: WorkspaceGroup) -> some View {
        switch group.listing {
        case .updateMac:
            card {
                Label {
                    Text(LocalizedStringResource("workspaces.oldMac"))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(Color("AccentText"))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("workspace.updateMac.\(group.id)")
            }
        case .empty:
            Text(LocalizedStringResource("workspaces.empty"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 4)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("workspace.empty.\(group.id)")
        case .rows, .hidden:
            EmptyView()
        }
        if group.showsRows {
            ForEach(group.rows) { row in
                Button {
                    actions.openWorkspace(row.id)
                } label: {
                    WorkspaceRowView(row: row, dimmed: group.state != .online)
                }
                .buttonStyle(.plain)
                .listRowInsets(Self.cardInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if group.canControl {
                        Button(role: .destructive) {
                            closing = row
                        } label: {
                            Label(String(localized: "workspaces.close"), systemImage: "xmark")
                        }
                        Button {
                            renaming = row
                        } label: {
                            Label(String(localized: "workspaces.rename"), systemImage: "pencil")
                        }
                        .tint(Color("AccentColor"))
                    }
                }
            }
        }
        if group.showsOtherSessions {
            otherSessions(of: group)
        }
    }

    private func otherSessions(of group: WorkspaceGroup) -> some View {
        Button {
            actions.openOtherSessions(group.id)
        } label: {
            HStack(spacing: 8) {
                Text(LocalizedStringResource("workspaces.other \(group.otherSessionCount)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(Self.cardInsets)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("workspace.otherSessions.\(group.id)")
    }

    private static let cardInsets = EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)

    /// A plain card in the list, for the notice rows.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return content()
            .background(Color.appSurface, in: shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
            .listRowInsets(Self.cardInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
