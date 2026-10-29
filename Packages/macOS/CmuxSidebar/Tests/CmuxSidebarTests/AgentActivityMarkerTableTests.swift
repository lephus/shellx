import CmuxSidebar
import Foundation
import Testing

// `#expect` cannot wrap a mutating call, so each call's result goes into a local first.
@Suite("Agent activity marker table")
struct AgentActivityMarkerTableTests {
    private let panel = UUID()
    private let otherPanel = UUID()

    // MARK: Turn end

    @Test func skillMarkerDoesNotSurviveStop() throws {
        var table = AgentActivityMarkerTable()
        table.apply(.skillInvoked(name: "brainstorming"), panelId: panel)
        #expect(try #require(table.markersByPanelId[panel]).kind == .skill)

        // A turn that ends while background work still runs keeps workflows only.
        let endedWithBackgroundWork = table.apply(.turnEnded(hasBackgroundWork: true), panelId: panel)
        #expect(endedWithBackgroundWork)
        #expect(table.markersByPanelId[panel] == nil)

        // A plain stop clears it as well.
        table.apply(.skillInvoked(name: "brainstorming"), panelId: panel)
        let endedIdle = table.apply(.turnEnded(hasBackgroundWork: false), panelId: panel)
        #expect(endedIdle)
        #expect(table.markersByPanelId.isEmpty)

        // A stop with nothing to clear changes nothing.
        let idleAgain = table.apply(.turnEnded(hasBackgroundWork: false), panelId: panel)
        let backgroundAgain = table.apply(.turnEnded(hasBackgroundWork: true), panelId: panel)
        #expect(!idleAgain)
        #expect(!backgroundAgain)
    }

    @Test func workflowMarkerSurvivesStopWithBackgroundWork() throws {
        var table = AgentActivityMarkerTable()
        table.apply(.workflowLaunched(name: "deep-review"), panelId: panel)
        let launched = try #require(table.markersByPanelId[panel])

        // Nothing changes, so the table reports no change.
        let changed = table.apply(.turnEnded(hasBackgroundWork: true), panelId: panel)
        #expect(!changed)
        let kept = try #require(table.markersByPanelId[panel])
        #expect(kept == launched)
        #expect(kept.kind == .workflow)
        #expect(kept.name == "deep-review")
    }

    @Test func workflowMarkerClearedByIdleStop() throws {
        var table = AgentActivityMarkerTable()
        table.apply(.workflowLaunched(name: "deep-review"), panelId: panel)
        #expect(try #require(table.markersByPanelId[panel]).kind == .workflow)

        let changed = table.apply(.turnEnded(hasBackgroundWork: false), panelId: panel)
        #expect(changed)
        #expect(table.markersByPanelId[panel] == nil)
    }

    // MARK: Turn start

    @Test func promptSubmitKeepsWorkflowMarker() throws {
        var table = AgentActivityMarkerTable()

        // A workflow may keep running in the background while the user chats.
        table.apply(.workflowLaunched(name: "deep-review"), panelId: panel)
        let launched = try #require(table.markersByPanelId[panel])
        let keptWorkflow = table.apply(.turnStarted(slashCommandName: nil), panelId: panel)
        #expect(!keptWorkflow)
        #expect(table.markersByPanelId[panel] == launched)

        // A skill does not outlive the turn it ran in.
        table.apply(.skillInvoked(name: "brainstorming"), panelId: otherPanel)
        let clearedSkill = table.apply(.turnStarted(slashCommandName: nil), panelId: otherPanel)
        #expect(clearedSkill)
        #expect(table.markersByPanelId[otherPanel] == nil)

        // A slash command replaces whatever marker was there, a workflow included.
        let replacedWorkflow = table.apply(.turnStarted(slashCommandName: "commit"), panelId: panel)
        #expect(replacedWorkflow)
        let replacement = try #require(table.markersByPanelId[panel])
        #expect(replacement.kind == .skill)
        #expect(replacement.name == "commit")
        #expect(replacement.generation > launched.generation)
    }

    @Test func slashCommandPromptSetsSkillMarker() throws {
        var table = AgentActivityMarkerTable()
        let placed = table.apply(.turnStarted(slashCommandName: "brainstorming"), panelId: panel)
        #expect(placed)
        let marker = try #require(table.markersByPanelId[panel])
        #expect(marker.kind == .skill)
        #expect(marker.name == "brainstorming")

        // A plain prompt on a pane without a marker changes nothing.
        let changed = table.apply(.turnStarted(slashCommandName: nil), panelId: otherPanel)
        #expect(!changed)
        #expect(table.markersByPanelId[otherPanel] == nil)
    }

    // MARK: Tool invocations

    @Test func toolInvocationsReplaceTheCurrentMarker() throws {
        var table = AgentActivityMarkerTable()
        table.apply(.workflowLaunched(name: "deep-review"), panelId: panel)

        let skillPlaced = table.apply(.skillInvoked(name: "pdf"), panelId: panel)
        #expect(skillPlaced)
        var marker = try #require(table.markersByPanelId[panel])
        #expect(marker.kind == .skill)
        #expect(marker.name == "pdf")

        let workflowPlaced = table.apply(.workflowLaunched(name: nil), panelId: panel)
        #expect(workflowPlaced)
        marker = try #require(table.markersByPanelId[panel])
        #expect(marker.kind == .workflow)
        #expect(marker.name == nil)

        // The same invocation again is still a new one.
        let before = marker.generation
        let repeated = table.apply(.workflowLaunched(name: nil), panelId: panel)
        #expect(repeated)
        #expect(try #require(table.markersByPanelId[panel]).generation > before)
    }

    @Test func sessionEndClearsEveryKindOfMarker() {
        var table = AgentActivityMarkerTable()
        table.apply(.workflowLaunched(name: "deep-review"), panelId: panel)
        table.apply(.skillInvoked(name: "pdf"), panelId: otherPanel)

        let workflowCleared = table.apply(.sessionEnded, panelId: panel)
        let skillCleared = table.apply(.sessionEnded, panelId: otherPanel)
        #expect(workflowCleared)
        #expect(skillCleared)
        #expect(table.markersByPanelId.isEmpty)

        let nothingLeft = table.apply(.sessionEnded, panelId: panel)
        #expect(!nothingLeft)
    }

    @Test func markersAreIndependentPerPanel() throws {
        var table = AgentActivityMarkerTable()
        table.apply(.skillInvoked(name: "pdf"), panelId: panel)
        table.apply(.workflowLaunched(name: "deep-review"), panelId: otherPanel)

        table.apply(.turnEnded(hasBackgroundWork: false), panelId: panel)
        #expect(table.markersByPanelId[panel] == nil)
        let survivor = try #require(table.markersByPanelId[otherPanel])
        #expect(survivor.kind == .workflow)
        #expect(survivor.name == "deep-review")
    }

    // MARK: Generations and removal

    @Test func generationIncreases() throws {
        var table = AgentActivityMarkerTable()
        table.apply(.skillInvoked(name: "pdf"), panelId: panel)
        let first = try #require(table.markersByPanelId[panel]).generation
        // The counter belongs to the whole table, so panels share it.
        table.apply(.workflowLaunched(name: "deep-review"), panelId: otherPanel)
        let second = try #require(table.markersByPanelId[otherPanel]).generation
        // The same name on the same panel is still a newer invocation.
        table.apply(.skillInvoked(name: "pdf"), panelId: panel)
        let third = try #require(table.markersByPanelId[panel]).generation
        #expect(first == 1)
        #expect(first < second)
        #expect(second < third)

        // Clearing and removing never rewind the counter.
        table.apply(.turnEnded(hasBackgroundWork: false), panelId: panel)
        table.removePanel(otherPanel)
        table.apply(.skillInvoked(name: "pdf"), panelId: panel)
        #expect(try #require(table.markersByPanelId[panel]).generation > third)
    }

    @Test func removePanelClears() throws {
        var table = AgentActivityMarkerTable()
        table.apply(.skillInvoked(name: "pdf"), panelId: panel)
        table.apply(.workflowLaunched(name: "deep-review"), panelId: otherPanel)

        let skillRemoved = table.removePanel(panel)
        #expect(skillRemoved)
        #expect(table.markersByPanelId[panel] == nil)
        #expect(try #require(table.markersByPanelId[otherPanel]).kind == .workflow)

        // A workflow marker goes with its panel too, and removing twice changes nothing.
        let workflowRemoved = table.removePanel(otherPanel)
        #expect(workflowRemoved)
        #expect(table.markersByPanelId.isEmpty)
        let removedAgain = table.removePanel(otherPanel)
        let removedUnknown = table.removePanel(UUID())
        #expect(!removedAgain)
        #expect(!removedUnknown)
    }

    @Test func freshTableIsEmpty() {
        let table = AgentActivityMarkerTable()
        #expect(table.markersByPanelId.isEmpty)
        #expect(table == AgentActivityMarkerTable())
    }
}
