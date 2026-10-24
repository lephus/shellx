public import Foundation

/// The skill and workflow marker of each pane, driven by hook signals.
///
/// A pane has at most one marker. ``apply(_:panelId:)`` moves a pane's marker
/// along as signals arrive, and every marker it places takes the next value of
/// one counter shared by the whole table, so a larger ``AgentActivityMarker/generation``
/// is always the newer invocation. The first generation is 1.
///
/// | Signal | The pane's marker afterwards |
/// |---|---|
/// | ``AgentActivityHookSignal/turnStarted(slashCommandName:)`` with a name | a new skill marker, replacing any marker |
/// | ``AgentActivityHookSignal/turnStarted(slashCommandName:)`` without a name | a skill marker is cleared; a workflow marker stays |
/// | ``AgentActivityHookSignal/skillInvoked(name:)`` | a new skill marker, replacing any marker |
/// | ``AgentActivityHookSignal/workflowLaunched(name:)`` | a new workflow marker, replacing any marker |
/// | ``AgentActivityHookSignal/turnEnded(hasBackgroundWork:)`` with background work | a skill marker is cleared; a workflow marker stays |
/// | ``AgentActivityHookSignal/turnEnded(hasBackgroundWork:)`` without | cleared |
/// | ``AgentActivityHookSignal/sessionEnded`` | cleared |
///
/// A workflow outlives the turn that launched it because it can keep running in
/// the background while the user keeps chatting, so only a turn that ends with no
/// background work, or the end of the session, clears it.
///
/// ```swift
/// var table = AgentActivityMarkerTable()
/// table.apply(.skillInvoked(name: "brainstorming"), panelId: panelId)
/// table.markersByPanelId[panelId]?.kind // .skill
/// table.apply(.turnEnded(hasBackgroundWork: false), panelId: panelId)
/// table.markersByPanelId[panelId] // nil
/// ```
public struct AgentActivityMarkerTable: Sendable, Equatable {
    /// The marker of every pane that currently has one, keyed by the pane's panel id.
    public private(set) var markersByPanelId: [UUID: AgentActivityMarker]

    /// The generation of the marker placed most recently, or 0 before the first.
    private var lastGeneration: UInt64

    /// Creates a table with no markers.
    public init() {
        markersByPanelId = [:]
        lastGeneration = 0
    }

    /// Moves a pane's marker along for a hook signal.
    ///
    /// - Parameters:
    ///   - signal: The signal the pane's agent hook reported.
    ///   - panelId: The panel the hook came from.
    /// - Returns: `true` when the table changed. Placing a marker always changes
    ///   it, because the marker takes a new generation; clearing changes it only
    ///   when there was a marker to clear.
    @discardableResult
    public mutating func apply(_ signal: AgentActivityHookSignal, panelId: UUID) -> Bool {
        switch signal {
        case .turnStarted(let slashCommandName):
            guard let slashCommandName else {
                return clearMarker(panelId: panelId, keepingWorkflow: true)
            }
            placeMarker(.skill, name: slashCommandName, panelId: panelId)
            return true
        case .skillInvoked(let name):
            placeMarker(.skill, name: name, panelId: panelId)
            return true
        case .workflowLaunched(let name):
            placeMarker(.workflow, name: name, panelId: panelId)
            return true
        case .turnEnded(let hasBackgroundWork):
            return clearMarker(panelId: panelId, keepingWorkflow: hasBackgroundWork)
        case .sessionEnded:
            return clearMarker(panelId: panelId, keepingWorkflow: false)
        }
    }

    /// Drops a pane's marker because the pane closed or left the workspace.
    ///
    /// - Parameter panelId: The panel that went away.
    /// - Returns: `true` when the pane had a marker, `false` when nothing changed.
    @discardableResult
    public mutating func removePanel(_ panelId: UUID) -> Bool {
        clearMarker(panelId: panelId, keepingWorkflow: false)
    }

    private mutating func placeMarker(_ kind: AgentActivityMarker.Kind, name: String?, panelId: UUID) {
        lastGeneration += 1
        markersByPanelId[panelId] = AgentActivityMarker(kind: kind, name: name, generation: lastGeneration)
    }

    /// Removes the pane's marker, except a workflow marker when asked to keep it.
    private mutating func clearMarker(panelId: UUID, keepingWorkflow: Bool) -> Bool {
        guard let marker = markersByPanelId[panelId] else { return false }
        if keepingWorkflow, marker.kind == .workflow { return false }
        markersByPanelId[panelId] = nil
        return true
    }
}
