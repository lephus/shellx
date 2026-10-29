import ShellXAppCore
import ShellXAppTestSupport
import XCTest
@testable import ShellX

/// The voice service the screens share: it stops every mic at once (an audio interruption, a lost
/// input, the app going to the background), and when the analyzer falls back, Settings names the
/// path presses really take.
@MainActor
final class VoiceServiceTests: XCTestCase {
    /// Answers with what the test sets, counting the questions.
    private final class Asker: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: VoiceCapabilities

        init(_ answer: VoiceCapabilities) {
            self.answer = answer
        }

        func set(_ answer: VoiceCapabilities) {
            lock.withLock { self.answer = answer }
        }

        func ask() -> VoiceCapabilities {
            lock.withLock { answer }
        }
    }

    private static let analyzer = VoiceCapabilities(analyzerSupportsLocale: true, legacyOnDevice: false, legacyAvailable: true)
    private static let server = VoiceCapabilities(analyzerSupportsLocale: false, legacyOnDevice: false, legacyAvailable: true)

    private func makeService(transcriber: FakeTranscriber, asker: Asker) throws -> VoiceService {
        let suite = "VoiceServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        VoiceLanguage.vietnamese.save(in: defaults)
        return VoiceService(
            transcriber: transcriber, permissions: FakeVoicePermissions(),
            cache: VoiceCapabilityCache { _ in asker.ask() }, meter: AudioLevelMeter(), latency: LatencyLog(),
            defaults: defaults, contextualStrings: { [] })
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func testCancelAllStopsEveryListeningMic() async throws {
        let transcriber = FakeTranscriber()
        let service = try makeService(transcriber: transcriber, asker: Asker(Self.server))
        let composer = service.makeModel()
        let sheet = service.makeModel(maxBytes: QuestionDraft.maxAnswerBytes)
        let idle = service.makeModel()

        await composer.press()
        transcriber.say("đang nói")
        let heard = await eventually { composer.phase == .listening(text: "đang nói") }
        XCTAssertTrue(heard)
        // One microphone: the sheet's press takes it over, as the real transcribers do.
        await sheet.press()
        let runs = transcriber.starts.map(\.run)
        XCTAssertEqual(transcriber.activeRun, runs[1])
        let handedOver = await eventually { transcriber.cancelledRuns.contains(runs[0]) }
        XCTAssertTrue(handedOver, "the composer's model let go of its run once it ended")

        await service.cancelAll()
        XCTAssertEqual(composer.phase, .idle)
        XCTAssertEqual(sheet.phase, .idle)
        XCTAssertEqual(idle.phase, .idle)
        XCTAssertNil(transcriber.activeRun, "nothing holds the microphone")
        XCTAssertEqual(Set(transcriber.cancelledRuns), Set(runs), "both runs stopped")
        let words = await composer.release()
        XCTAssertNil(words, "nothing heard before the interruption is sent afterwards")
    }

    func testAnalyzerFallbackMakesSettingsNameThePathUsed() async throws {
        let asker = Asker(Self.analyzer)
        let service = try makeService(transcriber: FakeTranscriber(), asker: asker)
        await service.refreshEngine()
        XCTAssertEqual(service.engine, .analyzer)

        // The analyzer failed to start; the probe now answers without it.
        asker.set(Self.server)
        await service.refreshEngine()
        XCTAssertEqual(service.engine, .analyzer, "the cached answer would still claim the iPhone")
        await service.analyzerFellBack(VoiceLanguage.vietnamese.locale)
        XCTAssertEqual(service.engine, .server, "Settings now says the voice goes to Apple's servers")
        XCTAssertEqual(VoiceSection.explanation(service.engine, language: .vietnamese),
                       VoiceSection.explanation(.server, language: .vietnamese))
    }
}
