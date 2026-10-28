import ShellXAppCore
import ShellXAppTestSupport
import SwiftUI
import XCTest
@testable import ShellX

/// The mic and what it says, driven through a `VoiceInputModel` over fakes: the composer idle,
/// listening (words and level bar), with cancel armed, with a permission denied and with no
/// recognizer; the question sheet after a spoken answer that matched no option; the plan sheet's
/// feedback mic; Settings › Voice. Each in light and dark (`dev.sh screenshots` writes them out).
@MainActor
final class MicButtonRenderTests: XCTestCase {
    private struct Rig {
        let service: VoiceService
        let model: VoiceInputModel
        let transcriber: FakeTranscriber
    }

    private static let serverOnly = VoiceCapabilities(analyzerSupportsLocale: false, legacyOnDevice: false, legacyAvailable: true)
    private static let spoken = "Chạy test cho shellx rồi tạo PR cho branch develop"

    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func makeRig(
        microphone: Bool = true, capabilities: VoiceCapabilities = serverOnly, maxBytes: Int = ComposerValidation.maxBytes
    ) throws -> Rig {
        let suite = "MicButtonRenderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let transcriber = FakeTranscriber()
        let service = VoiceService(
            transcriber: transcriber, permissions: FakeVoicePermissions(microphone: microphone),
            cache: VoiceCapabilityCache { _ in capabilities }, meter: AudioLevelMeter(level: 0.6), latency: LatencyLog(),
            defaults: defaults, contextualStrings: { [] })
        return Rig(service: service, model: service.makeModel(maxBytes: maxBytes), transcriber: transcriber)
    }

    private func composer(_ rig: Rig, draft: String = "") -> some View {
        VStack(spacing: 0) {
            Spacer()
            ComposerBar(text: .constant(draft), send: { _ in }, voice: rig.model)
        }
        .background(Color.appBackground)
        .environment(rig.service)
    }

    private func listen(_ rig: Rig, saying words: String = spoken) async {
        await rig.model.press()
        rig.transcriber.say(words)
        let heard = await eventually { rig.model.phase == .listening(text: words) }
        XCTAssertTrue(heard, "\(rig.model.phase)")
    }

    // MARK: - The composer's mic

    func testIdleRenders() throws {
        let rig = try makeRig()
        XCTAssertEqual(rig.model.phase, .idle)
        try assertRenders(composer(rig), name: "voice-idle")
    }

    func testListeningRenders() async throws {
        let rig = try makeRig()
        await listen(rig)
        try assertRenders(composer(rig), name: "voice-listening")
    }

    func testCancelArmedRenders() async throws {
        let rig = try makeRig()
        await listen(rig)
        rig.model.drag(dx: -120, dy: 0)
        XCTAssertEqual(rig.model.phase, .cancelArmed(text: Self.spoken))
        try assertRenders(composer(rig), name: "voice-cancel-armed")
    }

    func testDeniedRenders() async throws {
        let rig = try makeRig(microphone: false)
        await rig.model.press()
        XCTAssertEqual(rig.model.phase, .denied(.microphone))
        try assertRenders(composer(rig), name: "voice-denied")
    }

    func testUnavailableOpensTheKeyboardRenders() async throws {
        let rig = try makeRig(capabilities: .none)
        await rig.model.press()
        XCTAssertEqual(rig.model.phase, .unavailable)
        try assertRenders(composer(rig), name: "voice-unavailable")
        XCTAssertFalse(rig.model.wantsKeyboard, "the composer took the request and opened its field")
    }

    func testLimitReachedRenders() async throws {
        let rig = try makeRig()
        await rig.model.press()
        rig.transcriber.say(String(repeating: "giữ route v1, đừng xoá. ", count: 700))
        let stopped = await eventually { rig.model.limitReached }
        XCTAssertTrue(stopped)
        try assertRenders(composer(rig), name: "voice-limit")
    }

    func testLongDictationShowsItsNewestWords() {
        XCTAssertEqual(VoiceStatusView.newest(Self.spoken), Self.spoken)
        let long = String(repeating: "giữ route v1, đừng xoá. ", count: 40) + "rồi push"
        let shown = VoiceStatusView.newest(long)
        XCTAssertTrue(shown.hasPrefix("…"))
        XCTAssertTrue(shown.hasSuffix("rồi push"))
        XCTAssertLessThanOrEqual(shown.count, VoiceStatusView.shownCharacters + 1)
        XCTAssertFalse(shown.dropFirst().hasPrefix(" "), "starts at a word")
    }

    func testEachStateHasItsSymbol() {
        let symbols = [
            MicButton.symbol(for: .idle), MicButton.symbol(for: .listening(text: "")),
            MicButton.symbol(for: .cancelArmed(text: "")), MicButton.symbol(for: .denied(.speech)),
        ]
        XCTAssertEqual(Set(symbols).count, 4)
        for symbol in symbols { XCTAssertNotNil(UIImage(systemName: symbol), symbol) }
    }

    // MARK: - Sheets and Settings

    private static let question = MachinePendingItem(
        machineID: "m1", machineName: "MacBook Pro",
        item: PendingItem(
            requestId: "q1", kind: .question, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx",
            createdAtMs: 1,
            questions: [
                PendingQuestion(
                    id: "db", header: "Database", prompt: "Which database should the relay use?", multiSelect: false,
                    options: [
                        PendingQuestionOption(id: "pg", label: "Postgres"),
                        PendingQuestionOption(id: "lite", label: "SQLite"),
                    ])
            ]),
        actionable: true)

    func testQuestionSheetSpokenAnswerWithoutMatchRenders() throws {
        let rig = try makeRig(maxBytes: QuestionDraft.maxAnswerBytes)
        let words = "Dùng MongoDB đi"
        XCTAssertNil(Self.question.item.questions?.first?.option(matching: words))
        try assertRenders(
            QuestionAnswerSheet(
                item: Self.question, state: PendingSheetState(), send: { _ in }, close: {}, typing: ["db"],
                freeText: ["db": words], voice: rig.model, unmatched: ["db"]
            )
            .environment(rig.service),
            name: "pending-question-voice-no-match")
    }

    func testQuestionSheetListeningRenders() async throws {
        // The mic and its words sit in the bottom bar, outside the list.
        let rig = try makeRig(maxBytes: QuestionDraft.maxAnswerBytes)
        await listen(rig, saying: "cái thứ hai")
        try assertRenders(
            QuestionAnswerSheet(item: Self.question, state: PendingSheetState(), send: { _ in }, close: {}, voice: rig.model)
                .environment(rig.service),
            name: "pending-question-voice-listening")
    }

    func testPlanSheetFeedbackMicRenders() async throws {
        let rig = try makeRig(maxBytes: DecisionCenter.maxFeedbackBytes)
        await listen(rig, saying: "Giữ route v1, đừng xoá")
        let plan = MachinePendingItem(
            machineID: "m1", machineName: "MacBook Pro",
            item: PendingItem(
                requestId: "x1", kind: .exitPlan, agent: "claude", workspaceId: "ws", workspaceTitle: "relay",
                createdAtMs: 2, modes: ["manual", "deny"], planPreview: "1. Remove route v1.\n2. Ship."),
            actionable: true)
        try assertRenders(
            PlanReviewSheet(
                item: plan, state: PendingSheetState(), send: { _ in }, close: {}, revising: true, voice: rig.model
            )
            .environment(rig.service),
            name: "pending-plan-voice")
    }

    func testSettingsVoiceSectionRenders() async throws {
        let server = try makeRig()
        server.service.setLanguage(.vietnamese)
        await server.service.refreshEngine()
        XCTAssertEqual(server.service.engine, .server)
        try assertRenders(
            NavigationStack { SettingsView(email: "phu@example.com", signOut: {}) }.environment(server.service),
            name: "settings-voice-server")

        let none = try makeRig(capabilities: .none)
        await none.service.refreshEngine()
        XCTAssertNil(none.service.engine)
        XCTAssertTrue(none.service.engineKnown)
        try assertRenders(
            NavigationStack { SettingsView(email: "phu@example.com", signOut: {}) }.environment(none.service),
            name: "settings-voice-unavailable")
    }

    func testLanguageChoiceReachesEveryMic() throws {
        let rig = try makeRig()
        let other = rig.service.makeModel(maxBytes: QuestionDraft.maxAnswerBytes)
        rig.service.setLanguage(.vietnamese)
        rig.service.setLanguage(.english)
        XCTAssertEqual(rig.model.language, .english)
        XCTAssertEqual(other.language, .english)
        rig.service.setLanguage(.vietnamese)
        XCTAssertEqual(rig.model.language, .vietnamese)
        XCTAssertEqual(other.language, .vietnamese)
    }
}
