import CmuxSidebar
import Foundation
import Testing

@Suite("Agent name effect resolution")
struct AgentNameEffectResolutionTests {
    private let resolution = AgentNameEffectResolution()

    private let skill = AgentActivityMarker(kind: .skill, name: "pdf", generation: 4)
    private let workflow = AgentActivityMarker(kind: .workflow, name: "deep-review", generation: 9)

    private func effect(
        _ phase: AgentNameEffectInput.Phase,
        _ marker: AgentActivityMarker? = nil
    ) -> AgentNameEffect? {
        resolution.effect(for: AgentNameEffectInput(phase: phase, marker: marker))
    }

    @Test func needsInputHasNoEffect() {
        let markers: [AgentActivityMarker?] = [nil, skill, workflow]
        // Waiting for the user, a failure and an idle pane show nothing, whatever marker lingers.
        for phase in [AgentNameEffectInput.Phase.needsInput, .error, .idle] {
            for marker in markers {
                #expect(effect(phase, marker) == nil, "\(phase) with \(String(describing: marker))")
            }
        }
    }

    @Test func runningWithoutMarkerIsWorking() {
        #expect(effect(.running) == .working)
    }

    @Test func runningShowsTheMarkerHighlight() {
        #expect(effect(.running, skill) == .skill(name: "pdf", generation: 4))
        #expect(effect(.running, workflow) == .workflow(name: "deep-review", generation: 9))

        // An unnamed marker stays unnamed.
        let unnamed = AgentActivityMarker(kind: .skill, name: nil, generation: 5)
        #expect(effect(.running, unnamed) == .skill(name: nil, generation: 5))
    }

    @Test func backgroundWaitingShowsOnlyWorkflow() {
        #expect(effect(.backgroundWaiting, workflow) == .workflow(name: "deep-review", generation: 9))

        // A skill ends with its turn; waiting on background work is not a skill.
        #expect(effect(.backgroundWaiting, skill) == nil)
        #expect(effect(.backgroundWaiting) == nil)
    }

    @Test func markersFromATableResolveToo() throws {
        var table = AgentActivityMarkerTable()
        let panelId = UUID()
        table.apply(.skillInvoked(name: "brainstorming"), panelId: panelId)
        let issued = try #require(table.markersByPanelId[panelId])
        #expect(effect(.running, issued) == .skill(name: "brainstorming", generation: issued.generation))
    }

    @Test func strongestPrefersNewestHighlight() {
        #expect(resolution.strongest([]) == nil)
        #expect(resolution.strongest([.working, .working]) == .working)

        // A highlight beats working wherever it sits.
        let highlight = AgentNameEffect.skill(name: "a", generation: 2)
        #expect(resolution.strongest([.working, highlight]) == highlight)
        #expect(resolution.strongest([highlight, .working]) == highlight)

        // Between skills and workflows the newest generation wins, in any order.
        let effects: [AgentNameEffect] = [
            .working,
            .skill(name: "old", generation: 3),
            .workflow(name: "newest", generation: 7),
            .skill(name: "middle", generation: 5),
        ]
        #expect(resolution.strongest(effects) == .workflow(name: "newest", generation: 7))
        #expect(resolution.strongest(effects.reversed()) == .workflow(name: "newest", generation: 7))
        #expect(
            resolution.strongest([
                .workflow(name: "w", generation: 4),
                .skill(name: "s", generation: 9),
            ]) == .skill(name: "s", generation: 9)
        )

        // Equal generations keep the earlier effect, so the choice is deterministic.
        #expect(
            resolution.strongest([
                .skill(name: "first", generation: 6),
                .workflow(name: "second", generation: 6),
            ]) == .skill(name: "first", generation: 6)
        )
    }
}
