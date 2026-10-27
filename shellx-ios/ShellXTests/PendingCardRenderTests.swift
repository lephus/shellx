import ShellXAppCore
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// Pending cards of every kind and state, and the question, plan and full-text sheets, each in
/// light and dark (`dev.sh screenshots` writes them out in en and vi).
@MainActor
final class PendingCardRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    // MARK: - Items

    private static func mac(_ item: PendingItem, actionable: Bool = true) -> MachinePendingItem {
        MachinePendingItem(machineID: "m1", machineName: "MacBook Pro", item: item, actionable: actionable)
    }

    private static func permission(
        preview: String? = #"{"command":"git push origin feat/pairing","description":"Push the branch"}"#,
        modes: [String] = ["once", "always", "all", "deny"], tool: String = "Bash"
    ) -> PendingItem {
        PendingItem(
            requestId: "p1", kind: .permission, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx",
            toolName: tool, toolInputPreview: preview, createdAtMs: 1, modes: modes)
    }

    private static let edit = PendingItem(
        requestId: "e1", kind: .permission, agent: "codex", workspaceId: "ws", workspaceTitle: "web",
        toolName: "Edit",
        toolInputPreview: #"{"file_path":"/Users/me/web/app/page.tsx","old_string":"<h1>Hello</h1>","new_string":"<h1>Xin chào</h1>"}"#,
        createdAtMs: 2, modes: ["always", "deny"])

    private static let question = PendingItem(
        requestId: "q1", kind: .question, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx", createdAtMs: 3,
        questions: [
            PendingQuestion(
                id: "db", header: "Database", prompt: "Which database should the sync service use?", multiSelect: false,
                options: [
                    PendingQuestionOption(id: "pg", label: "Postgres", description: "Already runs on the VPS"),
                    PendingQuestionOption(id: "sq", label: "SQLite", description: "One file, no server"),
                ]),
            PendingQuestion(
                id: "checks", prompt: "Which checks run before a push?", multiSelect: true,
                options: [
                    PendingQuestionOption(id: "lint", label: "Lint"),
                    PendingQuestionOption(id: "unit", label: "Unit tests"),
                    PendingQuestionOption(id: "ui", label: "UI tests", description: "About 5 minutes"),
                ]),
        ])

    private static let planText = """
        ## Pair Macs by QR

        1. Add `PairingModel` and its **tests** first.
        2. Build the pairing sheet: scan, paste, confirm.
        3. "Your Macs" with unpair.

        ### Checks
        - `swift test` for ShellXAppCore
          - render tests in light and dark
        ```
        dev.sh test all
        ```
        """

    private static func plan(_ text: String? = planText, modes: [String] = ["manual", "auto_accept", "ultraplan", "deny"])
        -> PendingItem
    {
        PendingItem(
            requestId: "x1", kind: .exitPlan, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx",
            createdAtMs: 4, modes: modes, planPreview: text)
    }

    private static let unknown = PendingItem(
        requestId: "u1", kind: .other("teleport"), agent: "claude", workspaceId: "ws", workspaceTitle: "relay",
        createdAtMs: 5, modes: ["once"])

    private func cards(_ entries: [(MachinePendingItem, DecisionStatus?)], machines: Bool = false) -> some View {
        ScrollView { stack(entries, machines: machines) }
            .background(Color(uiColor: .systemGroupedBackground))
    }

    private func stack(_ entries: [(MachinePendingItem, DecisionStatus?)], machines: Bool = false) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                PendingCardView(item: entry.0, status: entry.1, showsMachineName: machines)
            }
        }
        .padding(16)
    }

    // MARK: - Cards

    func testEveryKindRenders() throws {
        try assertRenders(
            cards([(Self.mac(Self.permission()), nil), (Self.mac(Self.question), nil), (Self.mac(Self.plan()), nil)]),
            name: "pending-kinds")
        try assertRenders(
            cards([(Self.mac(Self.edit), nil), (Self.mac(Self.unknown), nil), (Self.mac(Self.permission(preview: nil)), nil)],
                  machines: true),
            name: "pending-kinds-more")
    }

    func testEveryStateRenders() throws {
        let states: [(String, DecisionStatus?, Bool)] = [
            ("sending", .sending, true), ("offline", .failed(.offline), false), ("no-answer", .failed(.noAnswer), true),
            ("rejected", .failed(.rejected), true), ("handled-elsewhere", .handledElsewhere, true),
            ("reconnecting", nil, false),
        ]
        for (label, status, actionable) in states {
            try assertRenders(
                cards([(Self.mac(Self.permission(), actionable: actionable), status)]), name: "pending-state-\(label)")
        }
    }

    func testCardRendersAtAccessibilityTextSize() throws {
        try assertRenders(
            cards([(Self.mac(Self.permission()), nil), (Self.mac(Self.question), .failed(.noAnswer))], machines: true)
                .environment(\.dynamicTypeSize, .accessibility3),
            name: "pending-ax3")
    }

    func testStatusLinesSayDifferentThings() {
        let statuses: [DecisionStatus] = [
            .sending, .handledElsewhere, .failed(.offline), .failed(.noAnswer), .failed(.rejected),
        ]
        let lines = statuses.compactMap { PendingCardStatusLine.line(status: $0, actionable: true, machineName: "Studio") }
        XCTAssertEqual(lines.count, statuses.count)
        let reconnecting = PendingCardStatusLine.line(status: nil, actionable: false, machineName: "Studio")
        XCTAssertEqual(Set((lines + [reconnecting].compactMap { $0 }).map(\.text)).count, 6)
        XCTAssertTrue(lines[2].text.contains("Studio"), "offline names the Mac")
        XCTAssertNil(PendingCardStatusLine.line(status: nil, actionable: true, machineName: "Studio"))
        XCTAssertNil(PendingCardStatusLine.line(status: .done, actionable: true, machineName: "Studio"))
        XCTAssertTrue(lines[3].offersRetry)
        XCTAssertEqual(
            PendingCardStatusLine.line(status: .failed(.noAnswer), actionable: false, machineName: "Studio")?.offersRetry,
            false, "no retry while reconnecting")
    }

    func testPermissionLayoutKeepsAllowAndDenyInTheRow() {
        let all = PendingCardView.PermissionLayout([.allowOnce, .deny, .allowAlways, .allowAllTools])
        XCTAssertEqual(all.buttons, [.deny, .allowOnce])
        XCTAssertEqual(all.menu, [.allowAlways, .allowAllTools])
        XCTAssertEqual(PendingCardView.PermissionLayout([.deny]).buttons, [.deny])
        XCTAssertEqual(PendingCardView.PermissionLayout([.deny]).menu, [])
    }

    func testLastingGrantIsNeverTheOneTapButton() {
        let noOnce = PendingCardView.PermissionLayout([.deny, .allowAlways, .allowAllTools])
        XCTAssertEqual(noOnce.buttons, [.deny], "without Allow (once) the row has Deny only")
        XCTAssertEqual(noOnce.menu, [.allowAlways, .allowAllTools], "lasting grants stay one step away")
        let alwaysOnly = PendingCardView.PermissionLayout([.allowAlways])
        XCTAssertEqual(alwaysOnly.buttons, [])
        XCTAssertEqual(alwaysOnly.menu, [.allowAlways])
    }

    func testHeadlineNamesWorkspaceAgentMacAndKind() {
        let item = Self.mac(Self.permission())
        XCTAssertEqual(
            PendingCardView.spokenHeadline(for: item, showsMachineName: false),
            "shellx, Claude Code, " + String(localized: "pending.kind.permission \("Bash")"))
        XCTAssertTrue(PendingCardView.spokenHeadline(for: item, showsMachineName: true).contains("MacBook Pro"))
        XCTAssertTrue(PendingCardView.spokenHeadline(for: Self.mac(Self.edit), showsMachineName: false).contains("Codex"))
    }

    func testLongPreviewRendersCollapsed() throws {
        // 8192 bytes of short lines mixing a command, Arabic (right to left) and emoji.
        var text = ""
        var line = 0
        while text.utf8.count < 9000 {
            line += 1
            text += "echo 'مرحبا' 🚀👩‍💻 ẩn \(line)\n"
        }
        let preview = PendingItem.truncatedPreview(text)
        XCTAssertGreaterThan(preview.utf8.count, 8180)
        XCTAssertGreaterThan(preview.split(separator: "\n").count, 150)
        let long = Self.mac(Self.permission(preview: preview))
        // The same first lines, four of them: three show, the fourth is cut.
        let four = Self.mac(Self.permission(preview: preview.split(separator: "\n").prefix(4).joined(separator: "\n")))

        let longHeight = height(of: stack([(long, nil)]))
        let fourHeight = height(of: stack([(four, nil)]))
        let oneLine = height(of: stack([(Self.mac(Self.permission(preview: "echo 'مرحبا' 🚀👩‍💻 ẩn 1")), nil)]))

        XCTAssertEqual(longHeight, fourHeight, accuracy: 1, "8 KB shows the same three lines as four lines do")
        XCTAssertGreaterThan(fourHeight, oneLine + 20, "three lines and Show more are taller than one line")
        XCTAssertLessThan(longHeight, 400, "the card stays a card")
        XCTAssertLessThanOrEqual(CommandPreview.collapsed(preview).text.count, CommandPreview.collapsedCharacters)
        XCTAssertTrue(CommandPreview.collapsed(preview).cut)
        try assertRenders(cards([(long, nil), (four, nil)]), name: "pending-long-preview")
    }

    /// The height the cards take at the snapshot width, after SwiftUI settled their state.
    private func height(of view: some View) -> CGFloat {
        let width = SnapshotWriter.size.width
        let host = UIHostingController(rootView: view.frame(width: width))
        let window = UIWindow(frame: CGRect(origin: .zero, size: SnapshotWriter.size))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.view.layoutIfNeeded()
        let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        window.isHidden = true
        return size.height
    }

    // MARK: - Sheets

    func testQuestionSheetBlocksAnswersOverTheLimit() {
        let questions = Self.question.questions ?? []
        var draft = QuestionDraft(questions: questions)
        draft.toggle(questionID: "db", label: "Postgres")
        let long = String(repeating: "ệ", count: 400)
        draft.setFreeText(questionID: "checks", text: long)
        XCTAssertTrue(draft.isComplete, "the draft holds the cut text")
        XCTAssertTrue(
            QuestionAnswerSheet.tooLong(draft, typed: ["checks": long]), "the field holds 1200 bytes: Send stays off")
        XCTAssertFalse(QuestionAnswerSheet.tooLong(draft, typed: ["checks": "Only lint"]))
        XCTAssertFalse(QuestionAnswerSheet.tooLong(draft, typed: [:]))

        let wide = PendingQuestion(
            id: "wide", prompt: "Pick", multiSelect: true,
            options: (0..<3).map { PendingQuestionOption(id: "o\($0)", label: String(repeating: "\($0)", count: 400)) })
        var picks = QuestionDraft(questions: [wide])
        for option in wide.options { picks.toggle(questionID: "wide", label: option.label) }
        XCTAssertTrue(QuestionAnswerSheet.tooLong(picks, typed: [:]), "joined labels past the limit")
    }

    func testQuestionSheetRendersAnswersOverTheLimit() throws {
        let item = Self.mac(Self.question)
        try assertRenders(
            QuestionAnswerSheet(
                item: item, state: PendingSheetState(), send: { _ in }, close: {}, page: 1, typing: ["checks"],
                freeText: ["checks": String(repeating: "Chỉ chạy lint thôi. ", count: 60)]),
            name: "pending-question-too-long")
        let wide = PendingItem(
            requestId: "w1", kind: .question, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx",
            createdAtMs: 6,
            questions: [
                PendingQuestion(
                    id: "wide", prompt: "Which notes go in the release?", multiSelect: true,
                    options: (1...3).map {
                        PendingQuestionOption(id: "o\($0)", label: "Note \($0): " + String(repeating: "x", count: 400))
                    })
            ])
        var picks = QuestionDraft(questions: wide.questions ?? [])
        for option in wide.questions?.first?.options ?? [] { picks.toggle(questionID: "wide", label: option.label) }
        try assertRenders(
            QuestionAnswerSheet(item: Self.mac(wide), state: PendingSheetState(), send: { _ in }, close: {}, draft: picks),
            name: "pending-question-choices-too-long")
    }

    func testQuestionSheetRenders() throws {
        let item = Self.mac(Self.question)
        try assertRenders(
            QuestionAnswerSheet(item: item, state: PendingSheetState(), send: { _ in }, close: {}),
            name: "pending-question")
        var draft = QuestionDraft(questions: Self.question.questions ?? [])
        draft.toggle(questionID: "db", label: "Postgres")
        draft.setFreeText(questionID: "checks", text: "Only lint, the UI tests are flaky today")
        try assertRenders(
            QuestionAnswerSheet(
                item: item, state: PendingSheetState(), send: { _ in }, close: {}, draft: draft, page: 1,
                typing: ["checks"]),
            name: "pending-question-other")
        try assertRenders(
            QuestionAnswerSheet(
                item: item, state: PendingSheetState(handledElsewhere: true, canSend: false), send: { _ in },
                close: {}, draft: draft),
            name: "pending-question-handled")
        try assertRenders(
            QuestionAnswerSheet(
                item: Self.mac(Self.question, actionable: false),
                state: PendingSheetState(canSend: false, actionable: false), send: { _ in }, close: {}, draft: draft,
                page: 1),
            name: "pending-question-reconnecting")
    }

    func testPlanSheetRenders() throws {
        let item = Self.mac(Self.plan())
        try assertRenders(
            PlanReviewSheet(item: item, state: PendingSheetState(), send: { _ in }, close: {}), name: "pending-plan")
        try assertRenders(
            PlanReviewSheet(
                item: item, state: PendingSheetState(), send: { _ in }, close: {}, revising: true,
                feedback: String(repeating: "Tách bước 2 ra. ", count: 260)),
            name: "pending-plan-revise-too-long")
        try assertRenders(
            PlanReviewSheet(
                item: item, state: PendingSheetState(status: .handledElsewhere, canSend: false), send: { _ in },
                close: {}),
            name: "pending-plan-handled")
        try assertRenders(
            PlanReviewSheet(
                item: Self.mac(Self.plan(nil, modes: ["manual", "deny"])), state: PendingSheetState(status: .sending, canSend: false),
                send: { _ in }, close: {}),
            name: "pending-plan-missing")
    }

    func testFullTextSheetRenders() throws {
        try assertRenders(FullTextSheet(item: Self.edit, close: {}), name: "pending-full-edit")
        try assertRenders(
            FullTextSheet(item: Self.permission(preview: String(repeating: "x", count: 8192)), close: {}),
            name: "pending-full-cut")
    }

    func testSheetKindFollowsTheItem() {
        XCTAssertEqual(PendingRoute.kind(for: Self.question), .question)
        XCTAssertEqual(PendingRoute.kind(for: Self.plan()), .plan)
        XCTAssertEqual(PendingRoute.kind(for: Self.permission()), .fullText)
        XCTAssertEqual(PendingRoute.kind(for: Self.plan(modes: [])), .fullText, "no plan button: show the text")
        XCTAssertEqual(PendingRoute.kind(for: Self.unknown), .fullText)
    }

    func testPlanMarkdownBlocks() {
        XCTAssertEqual(
            PlanMarkdownText.blocks(Self.planText),
            [
                .heading(level: 2, text: "Pair Macs by QR"),
                .numbered(number: "1", text: "Add `PairingModel` and its **tests** first.", level: 0),
                .numbered(number: "2", text: "Build the pairing sheet: scan, paste, confirm.", level: 0),
                .numbered(number: "3", text: "\"Your Macs\" with unpair.", level: 0),
                .heading(level: 3, text: "Checks"),
                .bullet(text: "`swift test` for ShellXAppCore", level: 0),
                .bullet(text: "render tests in light and dark", level: 1),
                .code("dev.sh test all"),
            ])
        XCTAssertEqual(PlanMarkdownText.blocks("one\ntwo\n\nthree"), [.paragraph("one\ntwo"), .paragraph("three")])
        XCTAssertEqual(
            PlanMarkdownText.summary("## Title\n\n1. First\n- item\n---\ntext"), "Title\n1. First\n• item\ntext",
            "a card's three lines carry text, not Markdown marks or blank lines")
        XCTAssertEqual(PlanMarkdownText.blocks("#hashtag\n---\n```\nopen"), [.paragraph("#hashtag"), .rule, .code("open")])
    }
}
