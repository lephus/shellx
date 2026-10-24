/// The effect a session or tab name plays for its agent's activity.
///
/// Skills and workflows are highlights: they outrank ``working``, and a view
/// plays a one-off flash whenever a highlight's `generation` changes.
/// ``AgentNameEffectResolution`` chooses the effect for a pane and the
/// strongest one for a group of panes.
public enum AgentNameEffect: Sendable, Equatable {
    /// The agent is working: a model turn or a tool call is in flight.
    case working

    /// The agent runs a skill.
    ///
    /// - Parameters:
    ///   - name: The skill name, or `nil` when the hook did not report one.
    ///   - generation: The ``AgentActivityMarker/generation`` of the marker behind the effect.
    case skill(name: String?, generation: UInt64)

    /// The agent runs a workflow.
    ///
    /// - Parameters:
    ///   - name: The workflow name, or `nil` when the hook did not report one.
    ///   - generation: The ``AgentActivityMarker/generation`` of the marker behind the effect.
    case workflow(name: String?, generation: UInt64)
}
