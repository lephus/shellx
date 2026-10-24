/// What one pane contributes to its name effect: its agent phase and its marker.
///
/// Pass it to ``AgentNameEffectResolution/effect(for:)`` to learn which
/// ``AgentNameEffect``, if any, the pane's name should play.
public struct AgentNameEffectInput: Sendable, Equatable {
    /// Where the pane's agent stands, as the sidebar already knows it.
    public enum Phase: Sendable, Equatable {
        /// No agent turn is running.
        case idle
        /// The agent is working on a turn.
        case running
        /// The agent's turn ended and it waits on background work it started.
        case backgroundWaiting
        /// The agent waits for the user, for example for a permission or an answer.
        case needsInput
        /// The agent's last turn failed.
        case error
    }

    /// The pane's agent phase.
    public let phase: Phase

    /// The pane's skill or workflow marker, or `nil` when it has none.
    public let marker: AgentActivityMarker?

    /// Creates the input for one pane.
    ///
    /// - Parameters:
    ///   - phase: The pane's agent phase.
    ///   - marker: The pane's marker from ``AgentActivityMarkerTable``, or `nil` when it has none.
    public init(phase: Phase, marker: AgentActivityMarker?) {
        self.phase = phase
        self.marker = marker
    }
}
