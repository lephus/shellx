/// Decides which effect a pane's name plays, and which one wins among several panes.
///
/// A pane's effect follows its agent phase and its marker. A session row shows
/// the strongest effect among the panes of its session.
///
/// | Phase | Effect |
/// |---|---|
/// | ``AgentNameEffectInput/Phase/idle``, ``AgentNameEffectInput/Phase/needsInput``, ``AgentNameEffectInput/Phase/error`` | none |
/// | ``AgentNameEffectInput/Phase/running`` | the marker's skill or workflow, else ``AgentNameEffect/working`` |
/// | ``AgentNameEffectInput/Phase/backgroundWaiting`` | the marker's workflow; none for no marker or a skill marker, because a skill ended with its turn |
public struct AgentNameEffectResolution: Sendable {
    /// Creates a resolution.
    public init() {}

    /// The effect a pane's name plays.
    ///
    /// - Parameter input: The pane's agent phase and marker.
    /// - Returns: The effect, or `nil` when the name should look ordinary.
    public func effect(for input: AgentNameEffectInput) -> AgentNameEffect? {
        switch input.phase {
        case .idle, .needsInput, .error:
            return nil
        case .running:
            guard let marker = input.marker else { return .working }
            return highlight(for: marker)
        case .backgroundWaiting:
            guard let marker = input.marker, marker.kind == .workflow else { return nil }
            return highlight(for: marker)
        }
    }

    /// The effect that wins among several, for a row that stands for several panes.
    ///
    /// A skill or workflow outranks ``AgentNameEffect/working``, and between two
    /// of them the larger generation, the newer invocation, wins. When generations
    /// tie, the earlier effect in `effects` wins.
    ///
    /// - Parameter effects: The effects of the panes the row stands for.
    /// - Returns: The strongest effect, or `nil` when `effects` is empty.
    public func strongest(_ effects: [AgentNameEffect]) -> AgentNameEffect? {
        var strongest: AgentNameEffect?
        for effect in effects {
            guard let current = strongest else {
                strongest = effect
                continue
            }
            if rank(of: effect) > rank(of: current) {
                strongest = effect
            }
        }
        return strongest
    }

    private func highlight(for marker: AgentActivityMarker) -> AgentNameEffect {
        switch marker.kind {
        case .skill:
            return .skill(name: marker.name, generation: marker.generation)
        case .workflow:
            return .workflow(name: marker.name, generation: marker.generation)
        }
    }

    /// Orders effects: highlights above working, then newer above older.
    private func rank(of effect: AgentNameEffect) -> (tier: Int, generation: UInt64) {
        switch effect {
        case .working:
            return (0, 0)
        case .skill(_, let generation), .workflow(_, let generation):
            return (1, generation)
        }
    }
}
