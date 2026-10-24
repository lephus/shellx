import Bonsplit
import CmuxSidebar
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Pane tabs carry their agent's activity (spec 2026-10-23 tab selection and
/// agent effects, §6.3 and §6.4): a running Claude pane's tab shimmers, a
/// skill or workflow lights it up with the marker's generation, "Show Loading
/// Spinner" off clears every tab, and a hidden workspace pauses its effects.
@Suite @MainActor struct ShellXTabActivitySyncTests {
    @Test func runningClaudePaneTabWorks() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let running = try #require(workspace.focusedPanelId)
        let quiet = try #require(
            workspace.newTerminalSplit(from: running, orientation: .horizontal, focus: false)?.id
        )
        Self.reportClaudeRunning(in: workspace, panelId: running)

        try Self.sync(workspace)

        #expect(Self.tab(of: running, in: workspace)?.activity == TabActivity(
            kind: .working,
            generation: 0,
            accessibilityLabel: "Thinking…"
        ))
        #expect(Self.tab(of: quiet, in: workspace) != nil)
        #expect(Self.tab(of: quiet, in: workspace)?.activity == nil)
    }

    @Test func skillMarkerHighlightsTheTab() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        workspace.applyAgentActivity(.skillInvoked(name: "brainstorming"), surfaceId: panelId)
        let marker = try #require(workspace.agentActivity.marker(forPanel: panelId))

        try Self.sync(workspace)

        #expect(Self.tab(of: panelId, in: workspace)?.activity == TabActivity(
            kind: .highlight,
            generation: marker.generation,
            accessibilityLabel: "Skill · brainstorming"
        ))
    }

    @Test func settingOffClearsTheActivity() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        try Self.sync(workspace)
        #expect(Self.tab(of: panelId, in: workspace)?.activity?.kind == .working)

        let updated = try Self.sync(workspace, showsAgentActivity: false)

        #expect(updated == 1)
        #expect(Self.tab(of: panelId, in: workspace) != nil)
        #expect(Self.tab(of: panelId, in: workspace)?.activity == nil)
    }

    /// An effect that did not change is not handed to Bonsplit again, so its
    /// animation and flash memory are left alone.
    @Test func unchangedActivityLeavesTheTabAlone() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)

        #expect(try Self.sync(workspace) == 1)
        #expect(try Self.sync(workspace) == 0)

        workspace.applyAgentActivity(.workflowLaunched(name: "release"), surfaceId: panelId)
        #expect(try Self.sync(workspace) == 1)
        #expect(Self.tab(of: panelId, in: workspace)?.activity?.kind == .highlight)
        #expect(try Self.sync(workspace) == 0)
    }

    /// Lifecycle and status entry changes alone, with no marker change, move
    /// the tab's effect through the observation the view runs.
    @Test(.timeLimit(.minutes(1)))
    func agentLifecycleAndStatusChangesResyncTheTabs() async throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        let text = try AgentActivityText.english()
        let (syncs, continuation) = AsyncStream<Void>.makeStream()
        let observation = Task { @MainActor in
            await WorkspaceContentView.observeAgentActivityChanges(of: workspace) {
                WorkspaceContentView.syncBonsplitAgentActivity(workspace, showsAgentActivity: true, text: text)
                continuation.yield(())
            }
        }
        defer { observation.cancel() }
        var iterator = syncs.makeAsyncIterator()
        // The first sync re-reads the state before the observation started.
        _ = await iterator.next()

        let owner = ControlSidebarPanelOwner.workspace(workspace)
        owner.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .running)
        while Self.tab(of: panelId, in: workspace)?.activity?.kind != .working, await iterator.next() != nil {}
        #expect(Self.tab(of: panelId, in: workspace)?.activity?.kind == .working)

        // A running turn whose status says it waits on background work stops working.
        owner.setStatusEntry(
            SidebarStatusEntry(key: "claude_code", value: "Waiting", icon: "bolt.fill", workState: .waiting),
            key: "claude_code",
            panelId: panelId
        )
        while Self.tab(of: panelId, in: workspace)?.activity != nil, await iterator.next() != nil {}
        #expect(Self.tab(of: panelId, in: workspace) != nil)
        #expect(Self.tab(of: panelId, in: workspace)?.activity == nil)
    }

    @Test func hiddenWorkspacePausesTabEffects() {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let controller = workspace.bonsplitController

        WorkspaceContentView.syncBonsplitPresentation(controller, isWorkspaceVisible: false)
        #expect(controller.isPresentationActive == false)

        WorkspaceContentView.syncBonsplitPresentation(controller, isWorkspaceVisible: true)
        #expect(controller.isPresentationActive)
    }

    // MARK: - Helpers

    /// Syncs the workspace's tabs with English activity words.
    @discardableResult
    private static func sync(_ workspace: Workspace, showsAgentActivity: Bool = true) throws -> Int {
        WorkspaceContentView.syncBonsplitAgentActivity(
            workspace,
            showsAgentActivity: showsAgentActivity,
            text: try AgentActivityText.english()
        )
    }

    /// The pane tab of a panel in the workspace's own split tree.
    private static func tab(of panelId: UUID, in workspace: Workspace) -> Bonsplit.Tab? {
        let controller = workspace.bonsplitController
        return controller.allPaneIds
            .flatMap { controller.tabs(inPane: $0) }
            .first { workspace.panelIdFromSurfaceId($0.id) == panelId }
    }

    /// Reports a running Claude turn for the pane the way the hook CLI does:
    /// a `set_status` row for `claude_code` and its lifecycle.
    private static func reportClaudeRunning(in workspace: Workspace, panelId: UUID) {
        let owner = ControlSidebarPanelOwner.workspace(workspace)
        owner.setStatusEntry(
            SidebarStatusEntry(key: "claude_code", value: "Running", icon: "bolt.fill", workState: .running),
            key: "claude_code",
            panelId: panelId
        )
        owner.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .running)
    }
}
