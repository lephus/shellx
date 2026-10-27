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
            slot: slot, primary: analyzer, fallback: legacy, usePrimary: { _ in analyzerReady },
            primaryFailed: { failures.add($0) })
        return Rig(router: router, analyzer: analyzer, legacy: legacy, failures: failures)
    }

    /// Holds the first `usePrimary` question until opened; later ones pass at once.
    private final class FirstCallGate: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private var isOpen = false
        private var held: CheckedContinuation<Void, Never>?

        var waiting: Bool { lock.withLock { held != nil } }

        func pass() async -> Bool {
            let first = lock.withLock { () -> Bool in
                calls += 1
                return calls == 1 && !isOpen
            }
            if first {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let now = lock.withLock { () -> Bool in
                        if isOpen { return true }
                        held = continuation
                        return false
                    }
                    if now { continuation.resume() }
                }
            }
            return true
        }

        func open() {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                isOpen = true
                defer { held = nil }
                return held
            }
            continuation?.resume()
        }
    }

    func testStaleStartHeldInReadinessNeverBlocksTheNewerPress() async throws {
        let slot = SpeechRunSlot()
        let analyzer = FakeTranscriber(slot: slot)
        let gate = FirstCallGate()
        let router = FallbackTranscriber(
            slot: slot, primary: analyzer, fallback: FakeTranscriber(slot: slot), usePrimary: { _ in await gate.pass() },
            primaryFailed: { _ in })
        let stale = SpeechRunID()
        let newer = SpeechRunID()

        // A quick tap: its readiness question is held, and the press is released meanwhile.
        let locale = Self.vietnamese
        let tap = Task { _ = try await router.start(run: stale, locale: locale, contextualStrings: []) }
        let asking = await eventually { gate.waiting }
        XCTAssertTrue(asking)
        await router.cancel(run: stale)
        // The hold right after: its start is held inside the analyzer.
        analyzer.holdStarts()
        let hold = Task { _ = try await router.start(run: newer, locale: locale, contextualStrings: []) }
        let holdHeld = await eventually { analyzer.startsWaiting == 1 }
        XCTAssertTrue(holdHeld)
        // Only now does the stale press get past its readiness question and begin inside.
        gate.open()
        let staleHeld = await eventually { analyzer.startsWaiting == 2 }
        XCTAssertTrue(staleHeld)
        analyzer.releaseStart(of: stale)
        try await tap.value
        analyzer.releaseStart(of: newer)
        try await hold.value

        XCTAssertEqual(analyzer.grantedRuns, [newer], "the newer press gets the microphone")
        XCTAssertEqual(slot.active, newer)
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
        XCTAssertNil(rig.legacy.activeRun, "finishing gave the microphone back")

        let other = SpeechRunID()
        _ = try await rig.router.start(run: other, locale: Self.vietnamese, contextualStrings: [])
        await rig.router.cancel(run: other)
        XCTAssertNil(rig.legacy.activeRun)
        XCTAssertFalse(rig.legacy.isRunning)
    }

    func testFinishReachesTheRunHoldingTheMicWhateverCameBetween() async throws {
        // One run holds the microphone while many presses that were cancelled while starting come
        // and go; finishing it must still give the microphone back.
        let rig = makeRig(analyzerReady: false)
        let live = SpeechRunID()
        _ = try await rig.router.start(run: live, locale: Self.vietnamese, contextualStrings: [])
        for _ in 0..<40 {
            let tap = SpeechRunID()
            await rig.router.cancel(run: tap)
            _ = try await rig.router.start(run: tap, locale: Self.vietnamese, contextualStrings: [])
        }
        XCTAssertEqual(rig.legacy.activeRun, live)
        rig.legacy.say("chạy test")
        rig.legacy.finalText = "Chạy test."
        let text = await rig.router.finish(run: live)
        XCTAssertEqual(text, "Chạy test.")
        XCTAssertNil(rig.legacy.activeRun, "nothing is left holding the microphone")
    }
}
