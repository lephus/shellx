import Bonsplit
import CmuxSidebar
import Combine
import Foundation

/// Pane tabs play their agent's activity (spec 2026-10-23 tab selection and agent effects,
/// §6.3 and §6.4).
///
/// Each tab of the workspace's own split tree carries the ``TabActivity`` of its pane's agent
/// name effect: a shimmer while the agent works, and a flowing highlight with one flash while it
/// runs a skill or a workflow. Bonsplit draws it only on bars that have a `titleEffectStyle`, so
/// light bars stay plain. "Show Loading Spinner" (`sidebar.showAgentActivity`) turns every tab's
/// activity off. The Dock and the nested remote-tmux trees get no activity: markers and agent
/// phases are keyed by the workspace's panel ids.
///
/// A sync runs when the view appears or gets a new workspace instance, when the setting flips,
/// and on every change to the workspace's skill and workflow markers, its panes' agent
/// lifecycles or their status entries; never per frame, terminal output or keystroke. The effects
/// animate on the render server, so the app adds no timers.
extension WorkspaceContentView {
    /// Gives each tab the activity its pane's agent plays now.
    func syncBonsplitAgentActivity() {
        Self.syncBonsplitAgentActivity(workspace, showsAgentActivity: showsAgentActivity)
    }

    /// Pauses the tab effects of a workspace that stays mounted but cannot be seen.
    func syncBonsplitPresentation() {
        Self.syncBonsplitPresentation(workspace.bonsplitController, isWorkspaceVisible: isWorkspaceVisible)
    }

    /// Resyncs the tabs' activity on every change that can move an effect, until cancelled.
    func observeAgentActivityChanges() async {
        await Self.observeAgentActivityChanges(of: workspace) {
            syncBonsplitAgentActivity()
        }
    }

    /// Gives each tab of the workspace's own split tree the activity its pane's agent plays.
    ///
    /// A tab is updated only when its activity changes, so an unchanged effect never restarts.
    ///
    /// - Parameters:
    ///   - workspace: The workspace whose split tree to update.
    ///   - showsAgentActivity: The "Show Loading Spinner" setting; off clears every tab.
    ///   - text: Where VoiceOver's activity words come from.
    /// - Returns: The number of tabs whose activity changed.
    @discardableResult
    static func syncBonsplitAgentActivity(
        _ workspace: Workspace,
        showsAgentActivity: Bool,
        text: AgentActivityText = AgentActivityText()
    ) -> Int {
        let controller = workspace.bonsplitController
        var updatedTabCount = 0
        for paneId in controller.allPaneIds {
            for tab in controller.tabs(inPane: paneId) {
                let effect = showsAgentActivity
                    ? workspace.panelIdFromSurfaceId(tab.id).flatMap { workspace.agentNameEffect(forPanel: $0) }
                    : nil
                let activity = effect.map { tabActivity(for: $0, text: text) }
                guard tab.activity != activity else { continue }
                controller.updateTab(tab.id, activity: .some(activity))
                updatedTabCount += 1
            }
        }
        return updatedTabCount
    }

    /// The tab activity for an agent name effect.
    ///
    /// Working shimmers; a skill or a workflow is a highlight that flashes once per marker
    /// generation. The sidebar row maps its effect the same way (`AgentNameEffect.tabActivity`).
    static func tabActivity(for effect: AgentNameEffect, text: AgentActivityText) -> TabActivity {
        effect.tabActivity(accessibilityLabel: text.text(for: effect))
    }

    /// Lets a workspace's tab effects animate only while the workspace is visible.
    ///
    /// Background workspaces stay mounted at zero opacity, where AppKit still calls their views
    /// visible.
    static func syncBonsplitPresentation(_ controller: BonsplitController, isWorkspaceVisible: Bool) {
        guard controller.isPresentationActive != isWorkspaceVisible else { return }
        controller.isPresentationActive = isWorkspaceVisible
    }

    /// Calls `onChange` on every change that can move a pane's agent name effect, until cancelled.
    ///
    /// The marker stream emits once on subscription, so the first call re-reads state that
    /// changed before the observation started.
    ///
    /// - Parameters:
    ///   - workspace: The workspace to watch.
    ///   - onChange: Called on the main actor after a marker, an agent lifecycle or a status
    ///     entry changes.
    static func observeAgentActivityChanges(
        of workspace: Workspace,
        onChange: @MainActor @escaping () -> Void
    ) async {
        let markerChanges = workspace.agentActivity.changes()
        let lifecycleChanges = workspace.sidebarAgentRuntimeObservation.changes()
        let statusEntryChanges = workspace.sidebarMetadata.statusEntriesPublisher
            .removeDuplicates()
            .map { _ in () }
            .values
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await _ in markerChanges {
                    if Task.isCancelled { break }
                    onChange()
                }
            }
            group.addTask { @MainActor in
                for await _ in lifecycleChanges {
                    if Task.isCancelled { break }
                    onChange()
                }
            }
            group.addTask { @MainActor in
                for await _ in statusEntryChanges {
                    if Task.isCancelled { break }
                    onChange()
                }
            }
        }
    }
}
