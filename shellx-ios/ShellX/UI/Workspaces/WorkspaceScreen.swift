import ShellXAppCore
import SwiftUI

/// What the workspace screen's controls do.
struct WorkspaceScreenActions {
    /// The user swiped to, or tapped, the chip with this terminal id.
    var select: (String) -> Void = { _ in }
    /// The workspace's new name, trimmed and not empty.
    var rename: (String) -> Void = { _ in }
    /// Confirmed: close the workspace and its terminals.
    var close: () -> Void = {}
    /// Confirmed: close the terminal tab with this id on the Mac, and stop what runs in it.
    var closeTab: (String) -> Void = { _ in }
    /// The user tapped ＋: open a new terminal tab in this workspace on the Mac.
    var createTerminal: () -> Void = {}
    /// "View as Terminal" (true) or "View as Chat" (false) on the agent chip with this terminal id.
    var showAsTerminal: (String, Bool) -> Void = { _, _ in }
}

/// What `•••` offers.
enum WorkspaceMenuItem: CaseIterable {
    case rename
    /// The agent chip shown shows its terminal instead of its chat.
    case viewAsTerminal
    /// The agent chip shown goes back from its terminal to its chat.
    case viewAsChat
    /// The tab of the chip shown, agent or shell; it asks to confirm first.
    case closeTab
    case closeWorkspace

    /// How the agent chip shown shows its page, when `•••` may switch it (its Mac shows terminals).
    enum AgentChip { case chat, terminal }

    /// The items in the menu's order: Rename; "View as Terminal" for an agent chip showing its chat, or "View as
    /// Chat" for one showing its terminal (one item whose words change, HIG: Menus); "Close Tab…" only while a chip
    /// shows and its Mac takes `terminal.close` (`WorkspaceListActions.canCloseTab`); "Close Workspace…".
    static func items(canCloseTab: Bool, agentChip: AgentChip? = nil) -> [WorkspaceMenuItem] {
        allCases.filter { item in
            switch item {
            case .rename, .closeWorkspace: true
            case .viewAsTerminal: agentChip == .chat
            case .viewAsChat: agentChip == .terminal
            case .closeTab: canCloseTab
            }
        }
    }

    var title: String {
        switch self {
        case .rename: String(localized: "workspace.menu.rename")
        case .viewAsTerminal: String(localized: "workspace.menu.viewAsTerminal")
        case .viewAsChat: String(localized: "workspace.menu.viewAsChat")
        case .closeTab: String(localized: "terminal.close.menu")
        case .closeWorkspace: String(localized: "workspace.menu.close")
        }
    }

    /// Shown red: Close Tab… and Close Workspace… only.
    var isDestructive: Bool { self == .closeTab || self == .closeWorkspace }
}

/// One workspace's screen, from plain values so render tests can show any state; `WorkspaceView` feeds
/// it from the hub.
///
/// - Bar: "‹ Workspace" (the system's back button), the workspace's name over its git branch in
///   monospace, and `•••` with "Rename Workspace", "View as Terminal" / "View as Chat" for an agent chip while
///   its Mac shows terminals (`canViewTerminals`), then, in red and each asking first, "Close Tab…" for
///   the chip shown while its Mac can close tabs (`canCloseTab`), and "Close Workspace…".
/// - Under it, the chips (`PaneChips`): one per terminal, the one shown highlighted, then ＋ (a new
///   terminal tab) while the Mac takes `terminal.create` (`canCreateTerminal`), dimmed while it is not
///   online or a new tab is on its way (`creatingTerminal`). While the Mac is online and can close tabs, a
///   long press on any chip offers "Close Tab…" for it too. Either way one confirmation names the tab and
///   says what closing it stops (HIG: Action sheets).
/// - Below, one page per chip, swiped sideways like the chips are tapped: a chip that runs an agent
///   shows the agent's chat (`agent`: the existing agent screen as a pane) unless it is shown as its
///   terminal (`shownAsTerminal`); any other page is `shell` (the terminal, `TerminalPane`). While a mic
///   listens (`pagingLocked`) the pages stay put.
/// - `notice`, when there is one, floats over the top of the pages (the pane shown was closed on the Mac).
struct WorkspaceScreen<AgentPane: View, ShellPane: View>: View {
    let title: String
    /// The git branch, when the Mac gave one.
    var branch: String?
    let panes: [WorkspacePane]
    /// The terminal id of the chip shown.
    let selected: String?
    /// The time the agents' states are read at.
    var now = Date()
    /// Rename and close reach the Mac: it is online and takes them.
    var canControl = true
    /// The Mac takes `terminal.close` (`WorkspaceListActions.canCloseTab`): any tab, agent or shell, can be
    /// closed from `•••` (the chip shown) and from a chip's long-press (while `canControl`).
    var canCloseTab = false
    /// The Mac takes `terminal.create`: the chips end with ＋, enabled while `canControl`.
    var canCreateTerminal = false
    /// The Mac shows terminals: `•••` offers View as Terminal / View as Chat on an agent chip.
    var canViewTerminals = false
    /// The agent chips shown as their terminal (`WorkspaceScreenModel.shownAsTerminal`).
    var shownAsTerminal: Set<String> = []
    /// ＋ was tapped and the Mac has not answered: ＋ is dimmed (`WorkspaceScreenModel.creatingTerminal`).
    var creatingTerminal = false
    /// A mic is listening: the pages do not follow a sideways drag, so a drag to the left on the mic (its
    /// cancel) never turns the page instead.
    var pagingLocked = false
    /// A short line over the pages, such as "Terminal closed on the Mac".
    var notice: AgentScreen.Notice?
    var actions = WorkspaceScreenActions()
    /// Why the last command did not work; the screen shows it until it is dismissed.
    @Binding var alert: WorkspaceAlert?
    /// The agent screen of a pane that runs an agent.
    @ViewBuilder let agent: (MachineSession) -> AgentPane
    /// The page of a shell chip, and of an agent chip shown as its terminal.
    @ViewBuilder let shell: (WorkspacePane) -> ShellPane

    @State private var renaming = false
    @State private var closing = false
    /// The tab the user chose to close, until the user confirms or cancels.
    @State private var closingTab: WorkspacePane?

    var body: some View {
        VStack(spacing: 0) {
            PaneChips(
                panes: panes, selected: selected, now: now, select: actions.select,
                close: canCloseTab && canControl ? { closingTab = $0 } : nil,
                add: canCreateTerminal ? actions.createTerminal : nil, addEnabled: canControl && !creatingTerminal)
            pager
                .overlay(alignment: .top) {
                    if let notice {
                        NoticeCapsule(text: notice.text)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: notice)
        }
        .background(Color.appBackground)
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titleBlock }
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .sheet(isPresented: $renaming) {
            WorkspaceRenameSheet(
                current: title,
                save: { name in
                    renaming = false
                    actions.rename(name)
                },
                cancel: { renaming = false })
        }
        .confirmationDialog(
            String(localized: "workspaces.close.title \(title)"), isPresented: $closing, titleVisibility: .visible
        ) {
            Button(String(localized: "workspaces.close"), role: .destructive, action: actions.close)
        } message: {
            Text(LocalizedStringResource("workspaces.close.confirm"))
        }
        .confirmationDialog(
            closingTab.map { String(localized: "terminal.close.title \(PaneChips.label(for: $0))") } ?? "",
            isPresented: Binding(get: { closingTab != nil }, set: { if !$0 { closingTab = nil } }),
            titleVisibility: .visible, presenting: closingTab
        ) { pane in
            Button(String(localized: "terminal.close"), role: .destructive) { actions.closeTab(pane.id) }
        } message: { _ in
            Text(LocalizedStringResource("terminal.close.confirm"))
        }
        .workspaceAlert($alert)
    }

    // MARK: - Bar

    /// The name over the branch.
    private var titleBlock: some View {
        VStack(spacing: 0) {
            Text(verbatim: title)
                .font(.headline)
                .lineLimit(1)
            if let branch, !branch.isEmpty {
                Text(verbatim: branch)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("workspace.title")
    }

    /// The chip shown: the one selected, else the first.
    private var shownPane: WorkspacePane? {
        let shown = selected ?? panes.first?.id
        return panes.first { $0.id == shown }
    }

    private var menu: some View {
        let items = WorkspaceMenuItem.items(canCloseTab: canCloseTab && shownPane != nil, agentChip: agentChip)
        return Menu {
            ForEach(items.filter { !$0.isDestructive }, id: \.self, content: menuButton)
            // The red items, which ask first, in a group of their own (HIG: Menus).
            Divider()
            ForEach(items.filter(\.isDestructive), id: \.self, content: menuButton)
        } label: {
            Label(String(localized: "workspace.menu"), systemImage: "ellipsis.circle")
        }
        .disabled(!canControl)
        .accessibilityIdentifier("workspace.menu")
    }

    /// How the agent chip shown shows its page, while its Mac shows terminals; nil for a shell chip.
    private var agentChip: WorkspaceMenuItem.AgentChip? {
        guard canViewTerminals, let pane = shownPane, pane.isAgent else { return nil }
        return shownAsTerminal.contains(pane.id) ? .terminal : .chat
    }

    private func menuButton(_ item: WorkspaceMenuItem) -> some View {
        Button(item.title, role: item.isDestructive ? .destructive : nil) {
            switch item {
            case .rename: renaming = true
            case .viewAsTerminal: if let pane = shownPane { actions.showAsTerminal(pane.id, true) }
            case .viewAsChat: if let pane = shownPane { actions.showAsTerminal(pane.id, false) }
            case .closeTab: closingTab = shownPane
            case .closeWorkspace: closing = true
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder private var pager: some View {
        if panes.isEmpty {
            Text(LocalizedStringResource("workspace.noTerminals"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("workspace.noTerminals")
        } else {
            TabView(selection: selection) {
                ForEach(panes) { pane in
                    page(of: pane).tag(pane.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(pagingLocked)
        }
    }

    private var selection: Binding<String> {
        Binding(get: { selected ?? panes.first?.id ?? "" }, set: { actions.select($0) })
    }

    @ViewBuilder private func page(of pane: WorkspacePane) -> some View {
        if let session = pane.session, !shownAsTerminal.contains(pane.id) {
            agent(session)
        } else {
            shell(pane)
        }
    }
}

/// What the workspace screen shows while the Mac has not listed the workspace yet: a new workspace's
/// answer can come before the list that holds it.
struct WorkspaceWaitingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationTitle(Text(LocalizedStringResource("workspaces.title")))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("workspace.loading")
    }
}

/// What the workspace screen shows when the workspace did not come: the Mac does not have it.
struct WorkspaceMissingView: View {
    let back: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(LocalizedStringResource("workspace.notFound"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Button(action: back) {
                Text(LocalizedStringResource("workspace.notFound.back"))
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("workspace.notFound.back")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .navigationTitle(Text(LocalizedStringResource("workspaces.title")))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workspace.notFound")
    }
}
