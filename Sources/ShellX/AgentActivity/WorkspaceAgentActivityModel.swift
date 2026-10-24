import CmuxSidebar
import Foundation

/// A workspace's skill and workflow markers, one per pane, kept from the raw
/// Claude Code hooks the app receives.
///
/// `agent.hook.enqueue` reads each hook event with ``AgentActivityHookObserver``
/// on the socket thread and hands its signal to the workspace on the main
/// actor, which moves the pane's marker here. `Workspace.agentNameEffect(forPanel:)`
/// combines a pane's marker with its agent phase into the effect its name plays.
///
/// Every change to ``table`` reaches ``changes()``. The sidebar rebuilds the
/// workspace's row snapshot from it through the per-workspace refresh that
/// status entry changes take (`sidebarWorkspaceObservations`); a pane tab bar
/// can resync its tabs from the same stream. Nothing observes the model through
/// SwiftUI or `objectWillChange`, so a marker change re-renders no other view.
@MainActor
final class WorkspaceAgentActivityModel {
    /// The marker of every pane that has one.
    private(set) var table = AgentActivityMarkerTable()

    /// The number of changes ``table`` has had.
    private(set) var revision: UInt64 = 0

    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// Moves a pane's marker for a Claude hook signal.
    ///
    /// - Parameters:
    ///   - signal: What the pane's Claude hook reported.
    ///   - panelId: The pane the hook came from.
    func apply(_ signal: AgentActivityHookSignal, panelId: UUID) {
        guard table.apply(signal, panelId: panelId) else { return }
        tableDidChange()
    }

    /// Drops a pane's marker because the pane closed or left the workspace.
    ///
    /// - Parameter panelId: The pane that went away.
    func removePanel(_ panelId: UUID) {
        guard table.removePanel(panelId) else { return }
        tableDidChange()
    }

    /// Drops every pane's marker because the workspace's agent state was reset.
    ///
    /// Observers hear one change for the whole reset, and none when there was
    /// no marker. Generations keep counting up, so a marker placed afterwards
    /// is still newer than any a view already flashed for.
    func removeAll() {
        var didChange = false
        for panelId in Array(table.markersByPanelId.keys) {
            didChange = table.removePanel(panelId) || didChange
        }
        guard didChange else { return }
        tableDidChange()
    }

    /// The pane's marker, or `nil` when it has none.
    func marker(forPanel panelId: UUID) -> AgentActivityMarker? {
        table.markersByPanelId[panelId]
    }

    /// Emits once on subscription, then after every change to ``table``.
    ///
    /// The first element lets a subscriber re-read a table that changed before
    /// it subscribed, as the sidebar's other observation streams do. Changes a
    /// subscriber has not read yet coalesce into one element.
    func changes() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.yield(())
            // AsyncStream termination is a nonisolated callback boundary.
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers[id] = nil }
            }
        }
    }

    private func tableDidChange() {
        revision &+= 1
        var terminatedIds: [UUID] = []
        for (id, continuation) in observers {
            if case .terminated = continuation.yield(()) {
                terminatedIds.append(id)
            }
        }
        for id in terminatedIds {
            observers[id] = nil
        }
    }
}
