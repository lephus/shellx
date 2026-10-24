import CmuxSettings
import CmuxSidebar
import Foundation
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The app keeps each pane's skill and workflow marker from raw Claude Code
/// hooks and hands the sidebar a name effect plus an activity line (spec
/// 2026-10-23 tab selection and agent effects, §6.3 and §6.6).
@Suite @MainActor struct ShellXAgentActivityTests {
    private static let skillPayload = #"{"tool_name":"Skill","tool_input":{"skill":"brainstorming"}}"#

    // MARK: - Reading hook events

    @Test func observerReadsClaudeSkillEvent() throws {
        let workspaceId = UUID()
        let surfaceId = UUID()
        let event = try #require(Self.hookEvent(agent: "claude", workspaceId: workspaceId, surfaceId: surfaceId))

        let observation = try #require(AgentActivityHookObserver().observation(for: event))

        #expect(observation.workspaceId == workspaceId)
        #expect(observation.surfaceId == surfaceId)
        #expect(observation.signal == .skillInvoked(name: "brainstorming"))
    }

    @Test func observerIgnoresCodex() throws {
        let workspaceId = UUID()
        let surfaceId = UUID()
        let claude = try #require(Self.hookEvent(agent: "claude", workspaceId: workspaceId, surfaceId: surfaceId))
        let codex = try #require(Self.hookEvent(agent: "codex", workspaceId: workspaceId, surfaceId: surfaceId))
        let observer = AgentActivityHookObserver()

        // The same event from Claude is read, so only the agent tells them apart.
        #expect(observer.observation(for: claude)?.signal == .skillInvoked(name: "brainstorming"))
        #expect(observer.observation(for: codex)?.signal == nil)
    }

    // MARK: - Markers follow the panes

    @Test func hookForAnUnknownSurfaceIsIgnored() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)

        workspace.applyAgentActivity(.skillInvoked(name: "brainstorming"), surfaceId: UUID())
        #expect(workspace.agentActivity.table.markersByPanelId.isEmpty)

        workspace.applyAgentActivity(.skillInvoked(name: "brainstorming"), surfaceId: panelId)
        #expect(workspace.agentActivity.marker(forPanel: panelId)?.name == "brainstorming")
    }

    @Test func closingPanelClearsMarker() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let first = try #require(workspace.focusedPanelId)
        let closing = try #require(
            workspace.newTerminalSplit(from: first, orientation: .horizontal, focus: false)?.id
        )
        // A workflow marker outlives turns, so only the close can clear it here.
        workspace.applyAgentActivity(.workflowLaunched(name: "release"), surfaceId: closing)
        #expect(workspace.agentActivity.marker(forPanel: closing)?.kind == .workflow)

        #expect(workspace.closePanel(closing, force: true))

        #expect(workspace.panels[closing] == nil)
        #expect(workspace.agentActivity.marker(forPanel: closing) == nil)
    }

    /// `reset_sidebar` clears every agent lifecycle; the markers go with them,
    /// or the pane's next Claude turn would replay an old workflow.
    @Test func resettingTheSidebarClearsMarkers() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let first = try #require(workspace.focusedPanelId)
        let second = try #require(
            workspace.newTerminalSplit(from: first, orientation: .horizontal, focus: false)?.id
        )
        Self.reportClaudeRunning(in: workspace, panelId: first)
        workspace.applyAgentActivity(.workflowLaunched(name: "release"), surfaceId: first)
        workspace.applyAgentActivity(.skillInvoked(name: "brainstorming"), surfaceId: second)
        let revision = workspace.agentActivity.revision

        workspace.resetSidebarContext(reason: "reset_sidebar")

        #expect(workspace.agentActivity.table.markersByPanelId.isEmpty)
        #expect(workspace.agentActivity.revision == revision + 1, "One row refresh for the whole reset")

        // A new turn without a slash command keeps a workflow marker, so a kept
        // one would show again here.
        Self.reportClaudeRunning(in: workspace, panelId: first)
        workspace.applyAgentActivity(.turnStarted(slashCommandName: nil), surfaceId: first)
        #expect(workspace.agentNameEffect(forPanel: first) == .working)
    }

    /// Resuming a hibernated agent clears its pane's agent state
    /// (`resumeAgentHibernation` calls `clearAgentLifecycleStates(panelId:)`);
    /// the pane's marker goes with it, or the resumed session's next turn
    /// replays an old workflow.
    @Test func clearingAPaneAgentStateClearsItsMarker() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        workspace.applyAgentActivity(.workflowLaunched(name: "release"), surfaceId: panelId)
        // A turn that ends with a background task running keeps the workflow marker.
        workspace.applyAgentActivity(.turnEnded(hasBackgroundWork: true), surfaceId: panelId)
        #expect(workspace.agentActivity.marker(forPanel: panelId)?.kind == .workflow)

        workspace.clearAgentLifecycleStates(panelId: panelId)

        #expect(workspace.agentActivity.marker(forPanel: panelId) == nil)
        // The resumed session's first turn keeps a workflow marker, so a kept one would show here.
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        workspace.applyAgentActivity(.turnStarted(slashCommandName: nil), surfaceId: panelId)
        #expect(workspace.agentNameEffect(forPanel: panelId) == .working)
    }

    @Test func removingAllMarkersNotifiesOnlyWhenThereWereMarkers() {
        let model = WorkspaceAgentActivityModel()
        model.removeAll()
        #expect(model.revision == 0)

        model.apply(.workflowLaunched(name: "release"), panelId: UUID())
        model.apply(.skillInvoked(name: "brainstorming"), panelId: UUID())
        let lastGeneration = model.table.markersByPanelId.values.map(\.generation).max() ?? 0
        model.removeAll()
        #expect(model.table.markersByPanelId.isEmpty)
        #expect(model.revision == 3)

        // Generations keep counting, so a view never mistakes a new marker for one it flashed.
        let panelId = UUID()
        model.apply(.skillInvoked(name: "review"), panelId: panelId)
        #expect((model.marker(forPanel: panelId)?.generation ?? 0) > lastGeneration)
    }

    // MARK: - Pane and workspace effects

    @Test func runningPanelWithSkillMarkerShowsSkill() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        #expect(workspace.agentNameEffect(forPanel: panelId) == .working)

        workspace.applyAgentActivity(.skillInvoked(name: "brainstorming"), surfaceId: panelId)

        let marker = try #require(workspace.agentActivity.marker(forPanel: panelId))
        #expect(workspace.agentNameEffect(forPanel: panelId) == .skill(name: "brainstorming", generation: marker.generation))
    }

    @Test func workspaceEffectPrefersNewestHighlight() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let working = try #require(workspace.focusedPanelId)
        let flowing = try #require(
            workspace.newTerminalSplit(from: working, orientation: .horizontal, focus: false)?.id
        )
        Self.reportClaudeRunning(in: workspace, panelId: working)
        Self.reportClaudeRunning(in: workspace, panelId: flowing)
        workspace.applyAgentActivity(.workflowLaunched(name: "release"), surfaceId: flowing)
        let workflow = try #require(workspace.agentActivity.marker(forPanel: flowing))

        #expect(workspace.agentNameEffect(forPanel: working) == .working)
        #expect(workspace.strongestAgentNameEffect == .workflow(name: "release", generation: workflow.generation))

        // A skill started later on the other pane is the newer highlight.
        workspace.applyAgentActivity(.skillInvoked(name: "brainstorming"), surfaceId: working)
        let skill = try #require(workspace.agentActivity.marker(forPanel: working))
        #expect(workspace.strongestAgentNameEffect == .skill(name: "brainstorming", generation: skill.generation))
    }

    /// A pane's agent phase decides whether its marker shows (spec §6.6).
    @Test(arguments: AgentActivityPaneCase.all)
    func paneEffectFollowsTheAgentPhase(_ paneCase: AgentActivityPaneCase) throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        let owner = ControlSidebarPanelOwner.workspace(workspace)
        owner.setStatusEntry(
            SidebarStatusEntry(
                key: paneCase.agentKey,
                value: "Status",
                icon: paneCase.icon,
                workState: paneCase.workState
            ),
            key: paneCase.agentKey,
            panelId: panelId
        )
        owner.setAgentLifecycle(key: paneCase.agentKey, panelId: panelId, lifecycle: paneCase.lifecycle)
        if let marker = paneCase.marker {
            workspace.agentActivity.apply(marker, panelId: panelId)
        }

        #expect(workspace.agentNameEffect(forPanel: panelId).map(AgentActivityEffectKind.init) == paneCase.expected)
    }

    // MARK: - Turn end

    // A turn's `Stop` and `SessionEnd` hooks are read the moment they arrive,
    // but the pane's lifecycle leaves running only when the delivery queue has
    // run the hook CLI for the same event, which can take seconds. In between,
    // a skill or workflow must not fall back to "Thinking…" and a plain turn
    // must not keep shimmering (spec §4, §6.3).

    @Test func skillTurnEndsWithoutFallingBackToWorking() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        let owner = ControlSidebarPanelOwner.workspace(workspace)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        workspace.applyAgentActivity(.skillInvoked(name: "brainstorming"), surfaceId: panelId)
        #expect(workspace.agentNameEffect(forPanel: panelId).map(AgentActivityEffectKind.init) == .skill)

        workspace.applyAgentActivity(.turnEnded(hasBackgroundWork: false), surfaceId: panelId)

        // The lifecycle still says running, but the turn is over.
        #expect(workspace.agentNameEffect(forPanel: panelId) == nil)
        let snapshot = Self.snapshot(of: workspace, colorScheme: .dark)
        #expect(snapshot.nameEffect == nil)
        #expect(snapshot.agentActivityText == nil)

        // The Stop's delivery settles the lifecycle.
        owner.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .idle)
        #expect(workspace.agentNameEffect(forPanel: panelId) == nil)

        // A turn that starts without a prompt, such as one woken by a background
        // task, reports only its lifecycle; it works again.
        owner.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .running)
        #expect(workspace.agentNameEffect(forPanel: panelId) == .working)
    }

    @Test func plainTurnStopsWorkingAtItsStop() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        #expect(workspace.agentNameEffect(forPanel: panelId) == .working)

        workspace.applyAgentActivity(.turnEnded(hasBackgroundWork: false), surfaceId: panelId)

        #expect(workspace.agentNameEffect(forPanel: panelId) == nil)
        #expect(Self.snapshot(of: workspace, colorScheme: .dark).agentActivityText == nil)

        // The next prompt starts a turn before any lifecycle report.
        workspace.applyAgentActivity(.turnStarted(slashCommandName: nil), surfaceId: panelId)
        #expect(workspace.agentNameEffect(forPanel: panelId) == .working)
    }

    @Test func sessionEndStopsTheEffectAtOnce() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        workspace.applyAgentActivity(.workflowLaunched(name: "release"), surfaceId: panelId)

        workspace.applyAgentActivity(.sessionEnded, surfaceId: panelId)

        #expect(workspace.agentNameEffect(forPanel: panelId) == nil)
    }

    @Test func workflowKeptByBackgroundWorkEndsWithItsLastTurn() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        let owner = ControlSidebarPanelOwner.workspace(workspace)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        workspace.applyAgentActivity(.workflowLaunched(name: "release"), surfaceId: panelId)
        let workflow = try #require(workspace.agentActivity.marker(forPanel: panelId))
        let rainbow = AgentNameEffect.workflow(name: "release", generation: workflow.generation)

        // The turn ends while the workflow keeps running in the background.
        workspace.applyAgentActivity(.turnEnded(hasBackgroundWork: true), surfaceId: panelId)
        #expect(workspace.agentNameEffect(forPanel: panelId) == rainbow)
        owner.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .backgroundWorkPending)
        #expect(workspace.agentNameEffect(forPanel: panelId) == rainbow)

        // The workflow finishes and wakes the agent for one more turn, which then ends.
        owner.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .running)
        #expect(workspace.agentNameEffect(forPanel: panelId) == rainbow)
        workspace.applyAgentActivity(.turnEnded(hasBackgroundWork: false), surfaceId: panelId)
        #expect(workspace.agentNameEffect(forPanel: panelId) == nil)
    }

    // MARK: - Sidebar snapshot

    @Test func snapshotCarriesNameEffectAndText() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)
        workspace.applyAgentActivity(.skillInvoked(name: "brainstorming"), surfaceId: panelId)
        let marker = try #require(workspace.agentActivity.marker(forPanel: panelId))

        let snapshot = Self.snapshot(of: workspace, colorScheme: .dark)

        let effect = AgentNameEffect.skill(name: "brainstorming", generation: marker.generation)
        #expect(snapshot.nameEffect == effect)
        // The words themselves are pinned in English by `activityTextNamesEachEffect`.
        #expect(snapshot.agentActivityText == AgentActivityText().text(for: effect))
    }

    @Test func effectsFollowShowAgentActivity() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportClaudeRunning(in: workspace, panelId: panelId)

        let shown = Self.snapshot(of: workspace, colorScheme: .dark)
        #expect(shown.nameEffect == .working)
        #expect(shown.agentActivityText == AgentActivityText().text(for: .working))

        let settingOff = Self.snapshot(of: workspace, colorScheme: .dark, showAgentActivity: false)
        #expect(settingOff.nameEffect == nil)
        #expect(settingOff.agentActivityText == nil)

        let lightSidebar = Self.snapshot(of: workspace, colorScheme: .light)
        #expect(lightSidebar.nameEffect == nil)
        #expect(lightSidebar.agentActivityText == nil)

        // Cached rows are rebuilt when the effects turn on or off.
        #expect(shown.presentationKey != settingOff.presentationKey)
        #expect(shown.presentationKey != lightSidebar.presentationKey)
    }

    @Test func activityTextNamesEachEffect() throws {
        let text = try AgentActivityText.english()

        #expect(text.text(for: .working) == "Thinking…")
        #expect(text.text(for: .skill(name: "brainstorming", generation: 1)) == "Skill · brainstorming")
        #expect(text.text(for: .skill(name: nil, generation: 1)) == "Skill")
        #expect(text.text(for: .workflow(name: "release", generation: 2)) == "Workflow · release")
        #expect(text.text(for: .workflow(name: nil, generation: 2)) == "Workflow")
    }

    // MARK: - Refresh

    @Test(.timeLimit(.minutes(1)))
    func markerChangesNotifySidebarObservers() async {
        let model = WorkspaceAgentActivityModel()
        var changes = model.changes().makeAsyncIterator()
        // A subscriber first re-reads the current table.
        #expect(await changes.next() != nil)

        let panelId = UUID()
        model.apply(.turnEnded(hasBackgroundWork: false), panelId: panelId)
        #expect(model.revision == 0, "Clearing a pane that has no marker must not refresh rows")

        model.apply(.workflowLaunched(name: "release"), panelId: panelId)
        #expect(model.revision == 1)
        guard model.revision == 1 else { return }
        #expect(await changes.next() != nil)
    }

    @Test func contextMenuKeepsTheNameEffectLive() {
        let current = SidebarWorkspaceSnapshotRefreshPolicyTests.snapshot(latestConversationMessage: "old message")
        var next = SidebarWorkspaceSnapshotRefreshPolicyTests.snapshot(latestConversationMessage: "new message")
        next.nameEffect = .working
        next.agentActivityText = "Thinking…"

        let decision = SidebarWorkspaceSnapshotRefreshPolicy().decision(
            current: current,
            next: next,
            force: false,
            contextMenuVisible: true
        )

        // The effect stands in for the loading spinner, which repaints while the menu is open.
        #expect(decision.workspaceSnapshotStorage?.nameEffect == .working)
        #expect(decision.workspaceSnapshotStorage?.agentActivityText == "Thinking…")
        #expect(decision.workspaceSnapshotStorage?.latestConversationMessage == "old message")
        #expect(decision.pendingWorkspaceSnapshot == next)
    }

    // MARK: - Helpers

    private static func hookEvent(
        agent: String,
        workspaceId: UUID,
        surfaceId: UUID
    ) -> AgentHookDeliveryEvent? {
        AgentHookDeliveryEvent(
            params: [
                "agent": agent,
                "subcommand": "pre-tool-use",
                "payload": skillPayload,
                "environment": [
                    "CMUX_WORKSPACE_ID": workspaceId.uuidString,
                    "CMUX_SURFACE_ID": surfaceId.uuidString,
                ],
            ],
            deliverySocketPath: "/tmp/shellx-agent-activity-tests.sock"
        )
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

    /// The sidebar row snapshot with the "Show Loading Spinner" setting as given.
    ///
    /// `showsAgentActivity` stays off: in ShellX it also needs the spinner
    /// experiment flag, which is off, and name effects follow the setting alone.
    private static func snapshot(
        of workspace: Workspace,
        colorScheme: ColorScheme,
        showAgentActivity: Bool = true
    ) -> SidebarWorkspaceSnapshotBuilder.Snapshot {
        let suiteName = "ShellXAgentActivityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(showAgentActivity, forKey: SidebarCatalogSection().showAgentActivity.userDefaultsKey)
        return SidebarWorkspaceSnapshotFactory(
            workspace: workspace,
            settings: SidebarTabItemSettingsSnapshot(defaults: defaults),
            showsAgentActivity: false,
            sidebarColorScheme: colorScheme
        ).makeSnapshot()
    }
}

extension AgentActivityText {
    /// The activity words in English, whatever language the test host runs in.
    static func english() throws -> AgentActivityText {
        let url = try #require(Bundle.main.url(forResource: "en", withExtension: "lproj"))
        return AgentActivityText(bundle: try #require(Bundle(url: url)))
    }
}

/// The kind of effect, without its name and generation.
enum AgentActivityEffectKind: Sendable, Equatable {
    case working, skill, workflow

    init(_ effect: AgentNameEffect) {
        switch effect {
        case .working: self = .working
        case .skill: self = .skill
        case .workflow: self = .workflow
        }
    }
}

/// One pane state and the effect its name should play.
struct AgentActivityPaneCase: Sendable, CustomTestStringConvertible {
    let name: String
    let agentKey: String
    let lifecycle: AgentHibernationLifecycleState
    var workState: SidebarAgentWorkState? = .running
    var icon: String? = "bolt.fill"
    var marker: AgentActivityHookSignal?
    let expected: AgentActivityEffectKind?

    var testDescription: String { name }

    static let all: [AgentActivityPaneCase] = [
        AgentActivityPaneCase(
            name: "running, no marker",
            agentKey: "claude_code",
            lifecycle: .running,
            expected: .working
        ),
        AgentActivityPaneCase(
            name: "running skill",
            agentKey: "claude_code",
            lifecycle: .running,
            marker: .skillInvoked(name: "a"),
            expected: .skill
        ),
        AgentActivityPaneCase(
            name: "running workflow",
            agentKey: "claude_code",
            lifecycle: .running,
            marker: .workflowLaunched(name: "w"),
            expected: .workflow
        ),
        AgentActivityPaneCase(
            name: "needs input",
            agentKey: "claude_code",
            lifecycle: .needsInput,
            marker: .skillInvoked(name: "a"),
            expected: nil
        ),
        AgentActivityPaneCase(
            name: "error icon",
            agentKey: "claude_code",
            lifecycle: .running,
            workState: nil,
            icon: "exclamationmark.triangle.fill",
            marker: .skillInvoked(name: "a"),
            expected: nil
        ),
        AgentActivityPaneCase(
            name: "running but waiting, workflow",
            agentKey: "claude_code",
            lifecycle: .running,
            workState: .waiting,
            marker: .workflowLaunched(name: "w"),
            expected: .workflow
        ),
        AgentActivityPaneCase(
            name: "running but waiting, skill",
            agentKey: "claude_code",
            lifecycle: .running,
            workState: .waiting,
            marker: .skillInvoked(name: "a"),
            expected: nil
        ),
        AgentActivityPaneCase(
            name: "running but waiting, no marker",
            agentKey: "claude_code",
            lifecycle: .running,
            workState: .waiting,
            expected: nil
        ),
        // Claude's turn that ends with a background task running reports this lifecycle.
        AgentActivityPaneCase(
            name: "background work, workflow",
            agentKey: "claude_code",
            lifecycle: .backgroundWorkPending,
            workState: .waiting,
            marker: .workflowLaunched(name: "w"),
            expected: .workflow
        ),
        AgentActivityPaneCase(
            name: "background work, no marker",
            agentKey: "claude_code",
            lifecycle: .backgroundWorkPending,
            workState: .waiting,
            expected: nil
        ),
        AgentActivityPaneCase(
            name: "idle",
            agentKey: "claude_code",
            lifecycle: .idle,
            workState: nil,
            marker: .workflowLaunched(name: "w"),
            expected: nil
        ),
        // Only Claude reports skills and workflows; another agent only works.
        AgentActivityPaneCase(
            name: "codex with a marker",
            agentKey: "codex",
            lifecycle: .running,
            marker: .skillInvoked(name: "a"),
            expected: .working
        ),
    ]
}
