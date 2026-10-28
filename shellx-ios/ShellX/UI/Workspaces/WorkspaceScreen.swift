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
}

/// What `•••` offers. Closing a single pane waits for the terminal version.
enum WorkspaceMenuItem: CaseIterable {
    case rename
    case closeWorkspace

    var title: String {
        switch self {
        case .rename: String(localized: "workspace.menu.rename")
        case .closeWorkspace: String(localized: "workspace.menu.close")
        }
    }
}

/// One workspace's screen, from plain values so render tests can show any state; `WorkspaceView` feeds
/// it from the hub.
///
/// - Bar: "‹ Workspace" (the system's back button), the workspace's name over its git branch in
///   monospace, and `•••` with "Rename Workspace" and "Close Workspace…" (red; it asks first).
/// - Under it, the chips (`PaneChips`): one per terminal, the one shown highlighted.
/// - Below, one page per chip, swiped sideways like the chips are tapped: a chip that runs an agent
///   shows the agent's chat (`agent`: the existing agent screen as a pane); any other shows
///   `ShellPanePlaceholder`.
struct WorkspaceScreen<AgentPane: View>: View {
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
    var actions = WorkspaceScreenActions()
    /// Why the last command did not work; the screen shows it until it is dismissed.
    @Binding var alert: WorkspaceAlert?
    /// The agent screen of a pane that runs an agent.
    @ViewBuilder let agent: (MachineSession) -> AgentPane

    @State private var renaming = false
    @State private var closing = false

    var body: some View {
        VStack(spacing: 0) {
            PaneChips(panes: panes, selected: selected, now: now, select: actions.select)
            pager
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

    private var menu: some View {
        Menu {
            Button(WorkspaceMenuItem.rename.title) { renaming = true }
            Divider()
            Button(WorkspaceMenuItem.closeWorkspace.title, role: .destructive) { closing = true }
        } label: {
            Label(String(localized: "workspace.menu"), systemImage: "ellipsis.circle")
        }
        .disabled(!canControl)
        .accessibilityIdentifier("workspace.menu")
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
        }
    }

    private var selection: Binding<String> {
        Binding(get: { selected ?? panes.first?.id ?? "" }, set: { actions.select($0) })
    }

    @ViewBuilder private func page(of pane: WorkspacePane) -> some View {
        if let session = pane.session {
            agent(session)
        } else {
            ShellPanePlaceholder()
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
