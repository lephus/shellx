import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// Answers to an agent's questions, built up on the phone and sent as positional `selections`
/// (PROTOCOL.md section 4, Decision).
final class QuestionDraftTests: XCTestCase {
    private let color = PendingQuestion(
        id: "color", header: "Colour", prompt: "Which colour?", multiSelect: false,
        options: [
            PendingQuestionOption(id: "blue", label: "Blue"), PendingQuestionOption(id: "gray", label: "Gray"),
        ])
    private let checks = PendingQuestion(
        id: "checks", prompt: "Which checks?", multiSelect: true,
        options: [
            PendingQuestionOption(id: "lint", label: "Lint"), PendingQuestionOption(id: "unit", label: "Unit"),
            PendingQuestionOption(id: "ui", label: "UI"),
        ])

    func testSingleSelectReplaces() {
        var draft = QuestionDraft(questions: [color])
        draft.toggle(questionID: "color", label: "Blue")
        draft.toggle(questionID: "color", label: "Gray")
        XCTAssertFalse(draft.isSelected(questionID: "color", label: "Blue"))
        XCTAssertTrue(draft.isSelected(questionID: "color", label: "Gray"))
        draft.toggle(questionID: "color", label: "Gray")
        XCTAssertTrue(draft.isSelected(questionID: "color", label: "Gray"), "a single choice stays chosen")
        XCTAssertEqual(draft.decision, .question(selections: ["Gray"]))
    }

    func testMultiSelectToggles() {
        var draft = QuestionDraft(questions: [checks])
        draft.toggle(questionID: "checks", label: "UI")
        draft.toggle(questionID: "checks", label: "Lint")
        draft.toggle(questionID: "checks", label: "Unit")
        draft.toggle(questionID: "checks", label: "Unit")
        XCTAssertEqual(draft.decision, .question(selections: ["Lint, UI"]))
        draft.toggle(questionID: "checks", label: "Lint")
        draft.toggle(questionID: "checks", label: "UI")
        XCTAssertFalse(draft.isComplete, "nothing chosen any more")
        XCTAssertNil(draft.decision)
    }

    func testMultiSelectJoinsLabels() {
        var draft = QuestionDraft(questions: [checks])
        for label in ["UI", "Unit", "Lint"] { draft.toggle(questionID: "checks", label: label) }
        XCTAssertEqual(draft.decision, .question(selections: ["Lint, Unit, UI"]), "in the options' order")
    }

    func testCompleteNeedsEveryQuestion() {
        var draft = QuestionDraft(questions: [color, checks])
        XCTAssertFalse(draft.isComplete)
        draft.toggle(questionID: "color", label: "Blue")
        XCTAssertFalse(draft.isComplete)
        XCTAssertTrue(draft.isAnswered(questionID: "color"))
        XCTAssertFalse(draft.isAnswered(questionID: "checks"))
        draft.setFreeText(questionID: "checks", text: "   ")
        XCTAssertFalse(draft.isComplete, "blank text answers nothing")
        draft.setFreeText(questionID: "checks", text: "Only the fast ones")
        XCTAssertTrue(draft.isComplete)
        XCTAssertFalse(QuestionDraft(questions: []).isComplete, "no question, nothing to send")
        XCTAssertNil(QuestionDraft(questions: []).decision)
    }

    func testDecisionKeepsQuestionOrder() {
        var draft = QuestionDraft(questions: [color, checks])
        draft.toggle(questionID: "checks", label: "Unit")
        draft.toggle(questionID: "color", label: "Gray")
        XCTAssertEqual(draft.decision, .question(selections: ["Gray", "Unit"]))
    }

    func testFreeTextAnswerIsPositional() {
        var draft = QuestionDraft(questions: [color, checks])
        draft.setFreeText(questionID: "color", text: "  Teal, like the logo \n")
        draft.toggle(questionID: "checks", label: "Lint")
        XCTAssertEqual(draft.decision, .question(selections: ["Teal, like the logo", "Lint"]))
        XCTAssertEqual(draft.freeText(questionID: "color"), "  Teal, like the logo \n", "the field keeps what was typed")
    }

    func testChoosingOptionClearsFreeText() {
        var draft = QuestionDraft(questions: [checks])
        draft.toggle(questionID: "checks", label: "Lint")
        draft.setFreeText(questionID: "checks", text: "None of these")
        XCTAssertFalse(draft.isSelected(questionID: "checks", label: "Lint"), "typed text replaces the choices")
        XCTAssertEqual(draft.decision, .question(selections: ["None of these"]))

        draft.toggle(questionID: "checks", label: "UI")
        XCTAssertEqual(draft.freeText(questionID: "checks"), "")
        XCTAssertEqual(draft.decision, .question(selections: ["UI"]))
    }

    func testFreeTextCutAt1024Bytes() {
        var draft = QuestionDraft(questions: [color])
        // "ệ" is 3 UTF-8 bytes: 341 of them make 1023 bytes, so a 342nd cannot fit whole.
        draft.setFreeText(questionID: "color", text: String(repeating: "ệ", count: 400))
        let kept = draft.freeText(questionID: "color")
        XCTAssertEqual(kept.utf8.count, 1023)
        XCTAssertEqual(kept, String(repeating: "ệ", count: 341))

        // A flag is one character of two scalars (8 bytes): it is kept whole or not at all.
        draft.setFreeText(questionID: "color", text: String(repeating: "a", count: 1020) + "🇻🇳")
        XCTAssertEqual(draft.freeText(questionID: "color"), String(repeating: "a", count: 1020))

        draft.setFreeText(questionID: "color", text: String(repeating: "b", count: 1024))
        XCTAssertEqual(draft.freeText(questionID: "color").utf8.count, 1024)
        XCTAssertEqual(QuestionDraft.maxAnswerBytes, 1024)
    }
}
