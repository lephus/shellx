import CmuxSidebar
import Testing

@Suite("OSC 7501 agent turn settlement")
struct ProgramStatusAgentSettlementTests {
    private let settlement = ProgramStatusAgentSettlement()

    private func store(_ reports: [ProgramStatusReport]) -> ProgramStatusRecordStore {
        var store = ProgramStatusRecordStore()
        for report in reports { store.apply(report) }
        return store
    }

    @Test func interruptClearEndsClaudeActivity() {
        // Esc: Claude Code clears its working record and runs no Stop hook.
        let working = store([ProgramStatusReport(state: .working, app: "claude-code")])
        var cleared = working
        cleared.apply(ProgramStatusReport(state: .clear))
        #expect(settlement.endedActivityStatusKeys(previous: working, current: cleared) == ["claude_code"])
        #expect(!settlement.isActive(statusKey: "claude_code", in: cleared))
    }

    @Test func doneAndIdleReportsEndClaudeActivity() {
        let working = store([ProgramStatusReport(state: .working, app: "claude-code")])
        for state in [ProgramStatusState.done, .idle, .error] {
            var ended = working
            ended.apply(ProgramStatusReport(state: state, app: "claude-code"))
            #expect(settlement.endedActivityStatusKeys(previous: working, current: ended) == ["claude_code"])
        }
    }

    @Test func blockedStaysActive() {
        // A permission prompt is not the end of the turn.
        let working = store([ProgramStatusReport(state: .working, app: "claude-code")])
        var blocked = working
        blocked.apply(ProgramStatusReport(state: .blocked, kind: .permission, app: "claude-code"))
        #expect(settlement.endedActivityStatusKeys(previous: working, current: blocked).isEmpty)
        #expect(settlement.isActive(statusKey: "claude_code", in: blocked))
    }

    @Test func childExitDropEndsActivity() {
        var store = store([ProgramStatusReport(state: .working, app: "claude-code")])
        let previous = store
        store.dropTransient()
        #expect(settlement.endedActivityStatusKeys(previous: previous, current: store) == ["claude_code"])
    }

    @Test func unknownAppsAndNewTurnsDoNotSettle() {
        let other = store([ProgramStatusReport(state: .working, app: "cargo")])
        var otherDone = other
        otherDone.apply(ProgramStatusReport(state: .done, app: "cargo"))
        #expect(settlement.endedActivityStatusKeys(previous: other, current: otherDone).isEmpty)

        // A pane that was idle and starts working has not ended anything.
        let idle = store([ProgramStatusReport(state: .done, app: "claude-code")])
        var working = idle
        working.apply(ProgramStatusReport(state: .working, app: "claude-code"))
        #expect(settlement.endedActivityStatusKeys(previous: idle, current: working).isEmpty)
        #expect(settlement.isActive(statusKey: "claude_code", in: working))
    }

    @Test func blockedToWorkingAnswersClaudesPrompt() {
        // Claude keeps its record blocked while a prompt waits and reports working once it is answered.
        let blocked = store([
            ProgramStatusReport(state: .working, app: "claude-code"),
            ProgramStatusReport(state: .blocked, kind: .question, app: "claude-code"),
        ])
        var answered = blocked
        answered.apply(ProgramStatusReport(state: .working, app: "claude-code"))
        #expect(settlement.answeredStatusKeys(previous: blocked, current: answered) == ["claude_code"])
        #expect(settlement.endedActivityStatusKeys(previous: blocked, current: answered).isEmpty)
    }

    @Test func onlyBlockedToWorkingAnswers() {
        let working = store([ProgramStatusReport(state: .working, app: "claude-code")])
        var blocked = working
        blocked.apply(ProgramStatusReport(state: .blocked, kind: .permission, app: "claude-code"))
        // working → blocked: the prompt waits.
        #expect(settlement.answeredStatusKeys(previous: working, current: blocked).isEmpty)
        // blocked → cleared or idle: Esc cancelled it, which the settlement handles.
        for state in [ProgramStatusState.clear, .idle, .done, .error] {
            var ended = blocked
            ended.apply(ProgramStatusReport(state: state, app: state == .clear ? nil : "claude-code"))
            #expect(settlement.answeredStatusKeys(previous: blocked, current: ended).isEmpty, "\(state)")
        }
        // A second record still blocked: the agent still waits.
        let twoBlocked = store([
            ProgramStatusReport(state: .blocked, kind: .permission, id: "", app: "claude-code"),
            ProgramStatusReport(state: .blocked, kind: .question, id: "ask"),
        ])
        var oneAnswered = twoBlocked
        oneAnswered.apply(ProgramStatusReport(state: .working, id: "ask"))
        #expect(settlement.answeredStatusKeys(previous: twoBlocked, current: oneAnswered).isEmpty)
        // Another program's prompt.
        let cargo = store([ProgramStatusReport(state: .blocked, kind: .question, app: "cargo")])
        var cargoWorking = cargo
        cargoWorking.apply(ProgramStatusReport(state: .working, app: "cargo"))
        #expect(settlement.answeredStatusKeys(previous: cargo, current: cargoWorking).isEmpty)
    }

    @Test func inheritedAppNameCounts() {
        let working = store([
            ProgramStatusReport(state: .done, id: "", app: "Claude-Code"),
            ProgramStatusReport(state: .working, id: "turn"),
        ])
        #expect(settlement.isActive(statusKey: "claude_code", in: working))
    }
}
