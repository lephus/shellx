import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// Which buttons a pending card offers, from the item's `kind` and `modes` alone.
final class PendingActionTests: XCTestCase {
    private func item(
        _ kind: PendingItem.Kind, modes: [String] = [], questions: [PendingQuestion]? = nil,
        preview: String? = nil, plan: String? = nil
    ) -> PendingItem {
        PendingItem(
            requestId: "r1", kind: kind, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx",
            toolName: "Bash", toolInputPreview: preview, createdAtMs: 1, modes: modes, questions: questions,
            planPreview: plan)
    }

    private func question(_ id: String, options: [String], multiSelect: Bool = false) -> PendingQuestion {
        PendingQuestion(
            id: id, prompt: "Pick one", multiSelect: multiSelect,
            options: options.map { PendingQuestionOption(id: $0, label: $0) })
    }

    func testPermissionButtonsFollowModesInOrder() {
        XCTAssertEqual(
            item(.permission, modes: ["all", "deny", "always", "once"]).actions,
            [.allowOnce, .deny, .allowAlways, .allowAllTools])
        XCTAssertEqual(item(.permission, modes: ["deny", "once"]).actions, [.allowOnce, .deny])
        XCTAssertEqual(item(.permission, modes: ["always"]).actions, [.allowAlways])
        XCTAssertEqual(PendingAction.allowOnce.decision, .permission(.once))
        XCTAssertEqual(PendingAction.deny.decision, .permission(.deny))
        XCTAssertEqual(PendingAction.allowAlways.decision, .permission(.always))
        XCTAssertEqual(PendingAction.allowAllTools.decision, .permission(.all))
    }

    func testBypassAndUnknownModesNeverShown() {
        XCTAssertEqual(
            item(.permission, modes: ["bypass", "once", "bypassPermissions", "yolo", "deny"]).actions,
            [.allowOnce, .deny])
        XCTAssertEqual(item(.permission, modes: ["bypass", "bypassPermissions"]).actions, [.openOnMac])
        XCTAssertEqual(
            item(.exitPlan, modes: ["bypassPermissions", "manual", "later"]).actions, [.approvePlan(.manual)])
    }

    func testEmptyModesOpenOnMac() {
        XCTAssertEqual(item(.permission).actions, [.openOnMac])
        XCTAssertEqual(item(.exitPlan, plan: "1. Do it").actions, [.openOnMac])
        XCTAssertNil(PendingAction.openOnMac.decision)
    }

    func testQuestionWithoutOptionsOpenOnMac() {
        XCTAssertEqual(item(.question, questions: [question("q1", options: ["A", "B"])]).actions, [.answer])
        XCTAssertNil(PendingAction.answer.decision, "the answer comes from the sheet")
        XCTAssertEqual(item(.question).actions, [.openOnMac], "no questions at all")
        XCTAssertEqual(item(.question, questions: []).actions, [.openOnMac])
        XCTAssertEqual(
            item(.question, questions: [question("q1", options: ["A"]), question("q2", options: [])]).actions,
            [.openOnMac], "one question has nothing to pick")
    }

    func testQuestionWithRepeatedIDsOpenOnMac() {
        // Answers are kept by question id: two questions sharing one could not be told apart.
        XCTAssertEqual(
            item(.question, questions: [question("q1", options: ["A"]), question("q1", options: ["B"])]).actions,
            [.openOnMac])
        XCTAssertEqual(
            item(.question, questions: [question("q1", options: ["A"]), question("q2", options: ["B"])]).actions,
            [.answer])
    }

    func testPlanApproveManualFirst() {
        XCTAssertEqual(
            item(.exitPlan, modes: ["ultraplan", "deny", "auto_accept", "manual"]).actions,
            [.approvePlan(.manual), .approvePlan(.autoAccept), .approvePlan(.ultraplan), .revisePlan, .rejectPlan])
        XCTAssertEqual(item(.exitPlan, modes: ["auto_accept"]).actions, [.approvePlan(.autoAccept)])
        XCTAssertEqual(item(.exitPlan, modes: ["deny"]).actions, [.revisePlan, .rejectPlan])
        XCTAssertEqual(PendingAction.approvePlan(.manual).decision, .exitPlan(.manual, feedback: nil))
        XCTAssertEqual(PendingAction.rejectPlan.decision, .exitPlan(.deny, feedback: nil))
        XCTAssertNil(PendingAction.revisePlan.decision, "feedback comes from the sheet")
    }

    func testUnknownKindOpenOnMacOnly() {
        XCTAssertEqual(
            item(.other("teleport"), modes: ["once", "deny", "manual"], questions: [question("q1", options: ["A"])])
                .actions,
            [.openOnMac])
    }

    // MARK: - What the card body shows

    func testPreviewShowsCommandOutOfToolInput() {
        let bash = item(.permission, preview: #"{"command":"git push origin main","description":"Push"}"#)
        XCTAssertEqual(bash.previewText, "git push origin main")
        let edit = item(.permission, preview: #"{"file_path":"/tmp/a.swift","old_string":"a","new_string":"b"}"#)
        XCTAssertEqual(edit.previewText, "/tmp/a.swift")
    }

    func testPreviewKeepsTextThatIsNotJSON() {
        // A preview cut at 8192 bytes is no longer valid JSON: it is shown as it came.
        let cut = #"{"command":"echo "#
        XCTAssertEqual(item(.permission, preview: cut).previewText, cut)
        XCTAssertEqual(item(.permission, preview: #"{"other":1}"#).previewText, #"{"other":1}"#)
        XCTAssertNil(item(.permission).previewText)
    }

    func testPreviewFieldsPutTheTellingOneFirst() {
        let edit = item(
            .permission, preview: #"{"new_string":"b","file_path":"/tmp/a.swift","old_string":"a","replace_all":false}"#)
        XCTAssertEqual(
            edit.previewFields?.map(\.key), ["file_path", "new_string", "old_string", "replace_all"])
        XCTAssertEqual(edit.previewFields?.first?.value, "/tmp/a.swift")
        XCTAssertEqual(edit.previewFields?.last?.value, "false")
        let nested = item(.permission, preview: #"{"command":"ls","env":{"A":"1"}}"#)
        XCTAssertEqual(nested.previewFields?.last?.value, #"{"A":"1"}"#)
        XCTAssertNil(item(.permission, preview: "plain text").previewFields)
        XCTAssertNil(item(.exitPlan, plan: #"{"command":"ls"}"#).previewFields, "only a tool's input has fields")
    }

    func testPreviewMayBeCutAtEitherLimit() {
        XCTAssertTrue(PendingItem.previewMayBeCut(String(repeating: "a", count: 8192)))
        XCTAssertTrue(PendingItem.previewMayBeCut(String(repeating: "ệ", count: 2730)), "8190 bytes: the next didn't fit")
        XCTAssertTrue(PendingItem.previewMayBeCut(String(repeating: "a", count: 1024)))
        XCTAssertFalse(PendingItem.previewMayBeCut(String(repeating: "a", count: 4000)))
        XCTAssertFalse(PendingItem.previewMayBeCut("git status"))
    }

    func testPreviewOfQuestionAndPlan() {
        let two = item(.question, questions: [question("q1", options: ["A"]), question("q2", options: ["B"])])
        XCTAssertEqual(two.previewText, "Pick one\nPick one")
        XCTAssertEqual(item(.exitPlan, plan: "1. Step").previewText, "1. Step")
    }
}
