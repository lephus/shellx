import CmuxSidebar
import Foundation

/// A workspace's skill and workflow markers, one per pane, kept from the raw
/// Claude Code hooks the app receives, and the panes whose Claude turn just ended.
///
/// `agent.hook.enqueue` reads each hook event with ``AgentActivityHookObserver``
/// on the socket thread and hands its signal to the workspace on the main
/// actor, which moves the pane's marker here. `Workspace.agentNameEffect(forPanel:)`
/// combines a pane's marker with its agent phase into the effect its name plays.
///
/// A `Stop` or `SessionEnd` hook arrives here before the pane's agent lifecycle
/// leaves running: the lifecycle waits for the delivery queue to run the hook
/// CLI for the same event. Until the lifecycle changes, the pane counts as a
/// turn that ended (``turnHasEnded(forPanel:)``), so its name does not fall back
/// to the working effect after a skill, or keep it after a plain turn. The
/// pane's next lifecycle change, or its next turn, skill or workflow hook,
/// clears that.
///
/// Every change to ``table`` or to the ended turns reaches ``changes()``. The
/// sidebar rebuilds the workspace's row snapshot from it through the
/// per-workspace refresh that status entry changes take
/// (`sidebarWorkspaceObservations`); a pane tab bar resyncs its tabs from the
/// same stream. Nothing observes the model through SwiftUI or
/// `objectWillChange`, so a change re-renders no other view.
@MainActor
final class WorkspaceAgentActivityModel {
    /// The marker of every pane that has one.
    private(set) var table = AgentActivityMarkerTable()

    /// The number of changes ``table`` and the ended turns have had.
    private(set) var revision: UInt64 = 0

    /// Panes whose Claude turn ended while their agent lifecycle has not changed since.
    private var turnEndedPanelIds: Set<UUID> = []

    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// Moves a pane's marker for a Claude hook signal.
    ///
    /// The end of a turn or a session also marks the pane's turn as ended; the
    /// start of a turn, a skill or a workflow unmarks it.
    ///
    /// - Parameters:
    ///   - signal: What the pane's Claude hook reported.
    ///   - panelId: The pane the hook came from.
    func apply(_ signal: AgentActivityHookSignal, panelId: UUID) {
        let tableChanged = table.apply(signal, panelId: panelId)
        let turnChanged: Bool
        switch signal {
        case .turnEnded, .sessionEnded:
            turnChanged = turnEndedPanelIds.insert(panelId).inserted
        case .turnStarted, .skillInvoked, .workflowLaunched:
            turnChanged = turnEndedPanelIds.remove(panelId) != nil
        }
        guard tableChanged || turnChanged else { return }
        stateDidChange()
    }

    /// Whether the pane's Claude turn ended and its agent lifecycle has not caught up yet.
    ///
    /// - Parameter panelId: A pane of the workspace.
    func turnHasEnded(forPanel panelId: UUID) -> Bool {
        turnEndedPanelIds.contains(panelId)
    }

    /// Unmarks the ended turn of every pane whose agent lifecycles differ between `old` and `new`.
    ///
    /// The workspace calls it on every write of its lifecycle map, before the write.
    ///
    /// - Parameters:
    ///   - old: The lifecycle map before the write.
    ///   - new: The lifecycle map after the write.
    func agentLifecyclesWillChange(
        from old: [UUID: [String: AgentHibernationLifecycleState]],
        to new: [UUID: [String: AgentHibernationLifecycleState]]
    ) {
        guard !turnEndedPanelIds.isEmpty else { return }
        let caughtUp = turnEndedPanelIds.filter { old[$0] != new[$0] }
        guard !caughtUp.isEmpty else { return }
        turnEndedPanelIds.subtract(caughtUp)
        stateDidChange()
    }

    /// Drops a pane's marker and ended turn because the pane closed, or its agent state was cleared.
    ///
    /// - Parameter panelId: The pane that went away.
    func removePanel(_ panelId: UUID) {
        let tableChanged = table.removePanel(panelId)
        let turnChanged = turnEndedPanelIds.remove(panelId) != nil
        guard tableChanged || turnChanged else { return }
        stateDidChange()
    }

    /// Drops every pane's marker and ended turn because the workspace's agent state was reset.
    ///
    /// Observers hear one change for the whole reset, and none when there was
    /// nothing to drop. Generations keep counting up, so a marker placed
    /// afterwards is still newer than any a view already flashed for.
    func removeAll() {
        var didChange = !turnEndedPanelIds.isEmpty
        turnEndedPanelIds.removeAll()
        for panelId in Array(table.markersByPanelId.keys) {
            didChange = table.removePanel(panelId) || didChange
        }
        guard didChange else { return }
        stateDidChange()
    }

    /// The pane's marker, or `nil` when it has none.
    func marker(forPanel panelId: UUID) -> AgentActivityMarker? {
        table.markersByPanelId[panelId]
    }

    /// Emits once on subscription, then after every change to ``table`` or the ended turns.
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

    private func stateDidChange() {
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
