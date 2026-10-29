/// A pane's current skill or workflow, kept while its agent runs it.
///
/// A marker is the app's record that Claude Code's hooks reported the pane's
/// agent invoking a skill, through the `Skill` tool or a `/name` command, or
/// launching a workflow. ``AgentActivityMarkerTable`` places and clears markers
/// from ``AgentActivityHookSignal`` values, and ``AgentNameEffectResolution``
/// reads them to choose the effect on the pane's name. A table numbers the
/// markers it places from one counter, so ``generation`` is only comparable
/// between markers of the same table.
public struct AgentActivityMarker: Sendable, Equatable {
    /// The kind of highlighted activity a marker stands for.
    public enum Kind: Sendable, Equatable {
        /// The agent runs a skill, invoked through the `Skill` tool or a `/name` command.
        case skill
        /// The agent runs a workflow, launched through the `Workflow` tool.
        case workflow
    }

    /// Whether the agent runs a skill or a workflow.
    public let kind: Kind

    /// The skill or workflow name, or `nil` when the hook payload carried none.
    public let name: String?

    /// The value of the table's counter when this marker was placed.
    ///
    /// Generations only grow within a table, so a larger one is always the newer
    /// invocation. A view can tell a fresh invocation from a repeat of the same
    /// name by seeing the generation change.
    public let generation: UInt64

    /// Creates a marker.
    ///
    /// Panes get their markers from ``AgentActivityMarkerTable``; build one by hand
    /// to feed ``AgentNameEffectInput`` in a test or a preview.
    ///
    /// - Parameters:
    ///   - kind: Whether the agent runs a skill or a workflow.
    ///   - name: The skill or workflow name, or `nil` when it is not known.
    ///   - generation: The counter value that orders this marker among the table's markers.
    public init(kind: Kind, name: String?, generation: UInt64) {
        self.kind = kind
        self.name = name
        self.generation = generation
    }
}
