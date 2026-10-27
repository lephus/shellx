import Foundation
import ShellXAppTestSupport
import XCTest

@testable import ShellXAppCore

/// The analyzer first when it can run the language, `SFSpeechRecognizer` otherwise. Only an error of
/// the analyzer itself makes a press fall back and stops offering the analyzer for that language; a
/// passing audio error (the session cannot activate during a call, no input) fails that press and
/// keeps the analyzer for the next one, so a language never moves to Apple's servers for nothing.
final class FallbackTranscriberTests: XCTestCase {
    /// Records which locales the analyzer was given up for.
    private final class Failures: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        var locales: [String] { lock.withLock { list } }
        func add(_ locale: Locale) { lock.withLock { list.append(locale.identifier) } }
    }

    private struct Rig {
        let router: FallbackTranscriber
        let analyzer: FakeTranscriber
        let legacy: FakeTranscriber
        let failures: Failures
    }

    private func makeRig(analyzerReady: Bool = true) -> Rig {
        let slot = SpeechRunSlot()
        let analyzer = FakeTranscriber(slot: slot)
        let legacy = FakeTranscriber(slot: slot)
        let failures = Failures()
        let router = FallbackTranscriber(
            primary: analyzer, fallback: legacy, usePrimary: { _ in analyzerReady },
            primaryFailed: { failures.add($0) })
        return Rig(router: router, analyzer: analyzer, legacy: legacy, failures: failures)
    }

    private static let vietnamese = Locale(identifier: "vi-VN")

    func testAnalyzerErrorFallsBackAndStopsOfferingIt() async throws {
        let rig = makeRig()
        rig.analyzer.startError = SpeechStartError.recognizer(URLError(.cannotLoadFromNetwork))
        let run = SpeechRunID()
        _ = try await rig.router.start(run: run, locale: Self.vietnamese, contextualStrings: [])
        XCTAssertEqual(rig.failures.locales, ["vi-VN"], "the analyzer is given up for vi-VN")
        XCTAssertEqual(rig.legacy.starts.map(\.run), [run], "this press goes through the fallback")
        XCTAssertEqual(rig.legacy.activeRun, run)
    }

    func testAudioErrorNeverDisablesTheAnalyzer() async throws {
        let rig = makeRig()
        rig.analyzer.startError = SpeechStartError.audio(URLError(.cannotConnectToHost))
        do {
            _ = try await rig.router.start(run: SpeechRunID(), locale: Self.vietnamese, contextualStrings: [])
            XCTFail("an audio error fails the press")
        } catch {}
        XCTAssertTrue(rig.failures.locales.isEmpty, "a passing audio error keeps the analyzer")
        XCTAssertTrue(rig.legacy.starts.isEmpty, "and does not send the voice to the fallback")

        // The next press tries the analyzer again.
        rig.analyzer.startError = nil
        let next = SpeechRunID()
        _ = try await rig.router.start(run: next, locale: Self.vietnamese, contextualStrings: [])
        XCTAssertEqual(rig.analyzer.grantedRuns, [next])
    }

    func testNotReadyGoesStraightToTheFallback() async throws {
        let rig = makeRig(analyzerReady: false)
        let run = SpeechRunID()
        _ = try await rig.router.start(run: run, locale: Self.vietnamese, contextualStrings: [])
        XCTAssertTrue(rig.analyzer.starts.isEmpty)
        XCTAssertEqual(rig.legacy.grantedRuns, [run])
        XCTAssertTrue(rig.failures.locales.isEmpty)
    }

    func testFinishAndCancelReachTheRunsTranscriber() async throws {
        let rig = makeRig(analyzerReady: false)
        let run = SpeechRunID()
        _ = try await rig.router.start(run: run, locale: Self.vietnamese, contextualStrings: [])
        rig.legacy.say("merge main")
        rig.legacy.finalText = "Merge main."
        let text = await rig.router.finish(run: run)
        XCTAssertEqual(text, "Merge main.")
        XCTAssertEqual(rig.legacy.finishCalls, 1)
        XCTAssertEqual(rig.analyzer.finishCalls, 0)

        let other = SpeechRunID()
        _ = try await rig.router.start(run: other, locale: Self.vietnamese, contextualStrings: [])
        await rig.router.cancel(run: other)
        XCTAssertNil(rig.legacy.activeRun)
        XCTAssertTrue(rig.legacy.cancelledRuns.contains(other))
    }
}
