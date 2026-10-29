import CmuxSidebar
import Foundation

/// The agent name effects of a workspace's panes (spec 2026-10-23 tab selection
/// and agent effects, §6.3 and §6.6).
///
/// A pane's effect combines its skill or workflow marker from ``agentActivity``
/// with its agent phase, read from the per-pane lifecycle states and status
/// entries that already drive the sidebar's spinner and status pill.
@MainActor
extension Workspace {
    /// Claude Code's agent status key. Only its turns report skills and workflows.
    private static let claudeAgentStatusKey = "claude_code"

    /// The effect the pane's name plays for its agent, or `nil` when it plays none.
    ///
    /// A pane whose agents do not include Claude Code never shows a marker, only
    /// the working effect: other agents report no skills or workflows. A pane whose
    /// Claude turn just ended does not work, even while its lifecycle still says
    /// running; a workflow kept by background work still plays.
    ///
    /// - Parameter panelId: A pane of this workspace.
    func agentNameEffect(forPanel panelId: UUID) -> AgentNameEffect? {
        paneAgentNameEffect(forPanel: panelId)?.effect
    }

    /// The strongest effect among the workspace's panes, for its sidebar row.
    ///
    /// A skill or workflow outranks working, and the most recently started one wins.
    var strongestAgentNameEffect: AgentNameEffect? {
        strongestAgentNameEffectSource?.effect
    }

    /// The strongest effect among the workspace's panes and the agent behind it, for its sidebar row.
    ///
    /// Skills and workflows come from Claude Code. When several panes work, Claude Code's row is
    /// the one that says so if one of them runs it; otherwise the first agent key in order.
    var strongestAgentNameEffectSource: AgentNameEffectSource? {
        let panes = agentLifecycleStatesByPanelId.keys.compactMap { panelId in
            paneAgentNameEffect(forPanel: panelId).map { pane in
                (panelId: panelId, effect: pane.effect, statusKey: pane.statusKey)
            }
        }
        guard let effect = AgentNameEffectResolution().strongest(panes.map(\.effect)) else { return nil }
        let driving = panes.filter { $0.effect == effect }
        let statusKey = driving.contains { $0.statusKey == Self.claudeAgentStatusKey }
            ? Self.claudeAgentStatusKey
            : driving.map(\.statusKey).min() ?? Self.claudeAgentStatusKey
        return AgentNameEffectSource(
            effect: effect,
            statusKey: statusKey
        )
    }

    /// Moves the marker of the pane a Claude hook came from.
    ///
    /// Hooks name their pane by `CMUX_SURFACE_ID`, which is the panel id or a
    /// surface inside the panel; `surfaceOwnershipTarget(for:)` resolves both.
    /// A surface that is not a live pane of this workspace is ignored.
    ///
    /// - Parameters:
    ///   - signal: What the hook reported.
    ///   - surfaceId: The hook's `CMUX_SURFACE_ID`.
    func applyAgentActivity(_ signal: AgentActivityHookSignal, surfaceId: UUID) {
        guard let panelId = surfaceOwnershipTarget(for: surfaceId)?.containerPanelID else { return }
        agentActivity.apply(signal, panelId: panelId)
    }

    /// The pane's effect and the status key of the agent behind it.
    private func paneAgentNameEffect(forPanel panelId: UUID) -> (effect: AgentNameEffect, statusKey: String)? {
        guard panels[panelId] != nil else { return nil }
        let lifecycles = (agentLifecycleStatesByPanelId[panelId] ?? [:]).filter {
            !AgentHibernationLifecycleStatusKeys.isManualKey($0.key)
        }
        guard !lifecycles.isEmpty else { return nil }
        let entries = agentStatusEntriesByPanelId[panelId] ?? [:]
        let marker = lifecycles[Self.claudeAgentStatusKey] == nil
            ? nil
            : agentActivity.marker(forPanel: panelId)
        let effect = AgentNameEffectResolution().effect(for: AgentNameEffectInput(
            phase: agentNamePhase(lifecycles: lifecycles, entries: entries),
            marker: marker
        ))
        guard let effect else { return nil }
        // The turn's Stop came before its lifecycle report: the agent no longer works.
        if effect == .working, agentActivity.turnHasEnded(forPanel: panelId) { return nil }
        guard effect == .working else { return (effect, Self.claudeAgentStatusKey) }
        let working = lifecycles.keys.filter { lifecycles[$0] == .running && entries[$0]?.workState != .waiting }
        let statusKey = working.contains(Self.claudeAgentStatusKey)
            ? Self.claudeAgentStatusKey
            : working.min() ?? Self.claudeAgentStatusKey
        return (effect, statusKey)
    }

    /// The pane's agent phase across the agents it runs.
    ///
    /// Waiting on the person, then a reported failure, silence the pane. One
    /// agent in a running turn makes it running, unless that turn's status entry
    /// says it waits on background work. A turn that ended with background work
    /// pending also waits: Claude reports that lifecycle when its `Stop` lists a
    /// running background task.
    private func agentNamePhase(
        lifecycles: [String: AgentHibernationLifecycleState],
        entries: [String: SidebarStatusEntry]
    ) -> AgentNameEffectInput.Phase {
        if lifecycles.values.contains(.needsInput) { return .needsInput }
        let reportsFailure = lifecycles.keys.contains { key in
            entries[key].map(SidebarCompactStatusGlyph.reportsError) ?? false
        }
        if reportsFailure { return .error }
        if lifecycles.contains(where: { $0.value == .running && entries[$0.key]?.workState != .waiting }) {
            return .running
        }
        if lifecycles.values.contains(where: { $0 == .running || $0 == .backgroundWorkPending }) {
            return .backgroundWaiting
        }
        return .idle
    }
}
