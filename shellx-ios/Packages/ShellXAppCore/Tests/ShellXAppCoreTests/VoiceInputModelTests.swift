import Foundation
import ShellXAppTestSupport
import XCTest

@testable import ShellXAppCore

/// Hold-to-talk: press starts listening and shows the words as they come; release returns them;
/// a drag to the left arms cancel; a swipe up before any word asks for the keyboard. Permissions,
/// a missing recognizer and the 16 384-byte limit each end the dictation visibly, and the keyboard
/// always stays usable.
@MainActor
final class VoiceInputModelTests: XCTestCase {
    private struct Rig {
        let model: VoiceInputModel
        let transcriber: FakeTranscriber
        let permissions: FakeVoicePermissions
        let clock: ManualClock
        let latency: LatencyLog
    }

    private static let everything = VoiceCapabilities(
        analyzerSupportsLocale: true, legacyOnDevice: true, legacyAvailable: true)

    private func makeRig(
        microphone: Bool = true, speech: Bool = true, capabilities: VoiceCapabilities = everything,
        language: VoiceLanguage = .vietnamese, maxBytes: Int = ComposerValidation.maxBytes
    ) -> Rig {
        let transcriber = FakeTranscriber()
        let permissions = FakeVoicePermissions(microphone: microphone, speech: speech)
        let clock = ManualClock()
        let latency = LatencyLog()
        let model = VoiceInputModel(
            transcriber: transcriber, permissions: permissions, capabilities: { _ in capabilities },
            language: language, contextualStrings: { ["shellx", "PR"] }, latency: latency, clock: clock,
            maxBytes: maxBytes)
        return Rig(model: model, transcriber: transcriber, permissions: permissions, clock: clock, latency: latency)
    }

    private func waitForPhase(_ model: VoiceInputModel, _ phase: VoiceInputModel.Phase) async {
        let reached = await eventually { model.phase == phase }
        XCTAssertTrue(reached, "phase is \(model.phase), expected \(phase)")
    }

    func testPressStartsListeningAndStreamsText() async throws {
        let rig = makeRig()
        await rig.model.press()
        XCTAssertEqual(rig.model.phase, .listening(text: ""))
        let start = try XCTUnwrap(rig.transcriber.starts.first)
        XCTAssertEqual(rig.transcriber.starts.count, 1)
        XCTAssertEqual(start.locale.identifier, "vi-VN")
        XCTAssertEqual(start.contextualStrings, ["shellx", "PR"])

        rig.transcriber.say("chạy test")
        await waitForPhase(rig.model, .listening(text: "chạy test"))
        rig.transcriber.say("chạy test cho shellx")
        await waitForPhase(rig.model, .listening(text: "chạy test cho shellx"))

        // A second press while listening changes nothing.
        await rig.model.press()
        XCTAssertEqual(rig.transcriber.starts.count, 1)
    }

    func testReleaseReturnsFinalText() async {
        let rig = makeRig(language: .english)
        await rig.model.press()
        XCTAssertEqual(rig.transcriber.starts.first?.locale.identifier, "en-US")
        rig.transcriber.say("run the tests for shell")
        await waitForPhase(rig.model, .listening(text: "run the tests for shell"))
        rig.transcriber.finalText = " Run the tests for shellx. "

        let text = await rig.model.release()
        XCTAssertEqual(text, "Run the tests for shellx.")
        XCTAssertEqual(rig.model.phase, .idle)
        XCTAssertEqual(rig.transcriber.finishCalls, 1)
        XCTAssertEqual(rig.transcriber.cancelCalls, 0)

        // When the recognizer has no final text, the last words heard are kept.
        await rig.model.press()
        rig.transcriber.say("open a PR")
        await waitForPhase(rig.model, .listening(text: "open a PR"))
        rig.transcriber.finalText = ""
        let fallback = await rig.model.release()
        XCTAssertEqual(fallback, "open a PR")
    }

    func testDragLeftThenReleaseCancels() async {
        let rig = makeRig()
        await rig.model.press()
        rig.transcriber.say("xoá nhánh main")
        await waitForPhase(rig.model, .listening(text: "xoá nhánh main"))

        rig.model.drag(dx: -79, dy: 0)
        XCTAssertEqual(rig.model.phase, .listening(text: "xoá nhánh main"))
        rig.model.drag(dx: -80, dy: 0)
        XCTAssertEqual(rig.model.phase, .cancelArmed(text: "xoá nhánh main"))
        // Back to the right: listening again.
        rig.model.drag(dx: -40, dy: 0)
        XCTAssertEqual(rig.model.phase, .listening(text: "xoá nhánh main"))
        rig.model.drag(dx: -120, dy: 10)
        XCTAssertEqual(rig.model.phase, .cancelArmed(text: "xoá nhánh main"))

        let text = await rig.model.release()
        XCTAssertNil(text)
        XCTAssertEqual(rig.model.phase, .idle)
        XCTAssertEqual(rig.transcriber.cancelCalls, 1)
        XCTAssertEqual(rig.transcriber.finishCalls, 0)
        XCTAssertFalse(rig.model.wantsKeyboard)
    }

    // MARK: - The hold gesture (MicHold)

    /// Does what `MicButton` does for a step of its hold; returns the words it would send.
    private func perform(_ step: MicHold.Step, on model: VoiceInputModel) async -> String? {
        switch step {
        case .press:
            await model.press()
            return nil
        case .release:
            return await model.release()
        case .cancel:
            model.drag(dx: -VoiceInputModel.cancelDistance, dy: 0)
            return await model.release()
        case .none:
            return nil
        }
    }

    /// The workspace pager (or a scroll view) takes the touch mid-dictation: SwiftUI resets the gesture's
    /// state without `onEnded`. Half-spoken words must not reach the agent.
    func testAHoldTakenAwayBeforeTheLiftSendsNothing() async {
        let rig = makeRig()
        var hold = MicHold()
        let pressed = await perform(hold.holdingChanged(true), on: rig.model)
        XCTAssertNil(pressed)
        rig.transcriber.say("xoá nhánh")
        await waitForPhase(rig.model, .listening(text: "xoá nhánh"))
        rig.transcriber.finalText = "xoá nhánh"

        // The state is reset, and no `onEnded` comes.
        let reset = hold.holdingChanged(false)
        let sentOnReset = await perform(reset, on: rig.model)
        let settled = hold.settle()
        let sentOnSettle = await perform(settled, on: rig.model)

        XCTAssertEqual([reset, settled], [.none, .cancel], "only a lift sends")
        XCTAssertNil(sentOnReset ?? sentOnSettle, "nothing goes to the agent")
        XCTAssertEqual(rig.model.phase, .idle)
        XCTAssertEqual(rig.transcriber.finishCalls, 0)
        XCTAssertEqual(rig.transcriber.cancelCalls, 1, "the microphone is given back")
    }

    /// The finger lifts: `onEnded` sends, whichever of the two signals SwiftUI delivers first, and the reset
    /// state that follows (or comes before) does nothing more.
    func testTheLiftSendsOnceWhicheverSignalComesFirst() async {
        for endedFirst in [true, false] {
            let rig = makeRig()
            var hold = MicHold()
            _ = await perform(hold.holdingChanged(true), on: rig.model)
            rig.transcriber.say("chạy test")
            await waitForPhase(rig.model, .listening(text: "chạy test"))
            rig.transcriber.finalText = "chạy test"

            var steps: [MicHold.Step] = []
            var sent: [String] = []
            // The mic settles on the main actor's next turn after the reset, so after both signals.
            for signal in (endedFirst ? ["ended", "reset"] : ["reset", "ended"]) + ["settle"] {
                let step =
                    switch signal {
                    case "ended": hold.ended()
                    case "reset": hold.holdingChanged(false)
                    default: hold.settle()
                    }
                steps.append(step)
                if let words = await perform(step, on: rig.model) { sent.append(words) }
            }

            XCTAssertEqual(sent, ["chạy test"], "ended first: \(endedFirst), steps \(steps)")
            XCTAssertEqual(rig.transcriber.finishCalls, 1)
        }
    }

    func testTheHoldIgnoresSignalsWithoutAPress() {
        var hold = MicHold()
        XCTAssertEqual(hold.ended(), .none, "a lift with no hold before it")
        XCTAssertEqual(hold.holdingChanged(false), .none)
        XCTAssertEqual(hold.settle(), .none)
        XCTAssertEqual(hold.holdingChanged(true), .press)
        XCTAssertEqual(hold.holdingChanged(true), .none, "already down")
    }

    func testSwipeUpBeforeWordsAsksKeyboard() async {
        let rig = makeRig()
        await rig.model.press()
        rig.model.drag(dx: 0, dy: -59)
        XCTAssertFalse(rig.model.wantsKeyboard)
        rig.model.drag(dx: 5, dy: -60)
        XCTAssertTrue(rig.model.wantsKeyboard)
        XCTAssertEqual(rig.model.phase, .idle)
        let cancelled = await eventually { rig.transcriber.cancelCalls == 1 }
        XCTAssertTrue(cancelled, "listening stops")
        let text = await rig.model.release()
        XCTAssertNil(text)

        // Once words came, a swipe up keeps listening.
        rig.model.wantsKeyboard = false
        await rig.model.press()
        rig.transcriber.say("merge main")
        await waitForPhase(rig.model, .listening(text: "merge main"))
        rig.model.drag(dx: 0, dy: -200)
        XCTAssertFalse(rig.model.wantsKeyboard)
        XCTAssertEqual(rig.model.phase, .listening(text: "merge main"))
    }

    func testEmptyTranscriptReturnsNil() async {
        let rig = makeRig()
        await rig.model.press()
        rig.transcriber.finalText = "  \n "
        let text = await rig.model.release()
        XCTAssertNil(text)
        XCTAssertEqual(rig.model.phase, .idle)
        XCTAssertNil(rig.model.firstWordLatency)
    }

    func testDeniedMicrophoneShowsDenied() async {
        let rig = makeRig(microphone: false)
        await rig.model.press()
        XCTAssertEqual(rig.model.phase, .denied(.microphone))
        XCTAssertTrue(rig.transcriber.starts.isEmpty)
        let text = await rig.model.release()
        XCTAssertNil(text)
        XCTAssertEqual(rig.model.phase, .denied(.microphone), "the reason stays until the next press")

        let speech = makeRig(speech: false)
        await speech.model.press()
        XCTAssertEqual(speech.model.phase, .denied(.speech))
        XCTAssertTrue(speech.transcriber.starts.isEmpty)
        XCTAssertEqual(speech.permissions.microphoneRequests, 1)
        XCTAssertEqual(speech.permissions.speechRequests, 1)

        // Granted later (in Settings): the next press listens.
        speech.permissions.speechGranted = true
        await speech.model.press()
        XCTAssertEqual(speech.model.phase, .listening(text: ""))
        XCTAssertEqual(speech.transcriber.starts.count, 1)
    }

    func testUnavailableNeverBlocksKeyboard() async {
        let rig = makeRig(capabilities: .none)
        await rig.model.press()
        XCTAssertEqual(rig.model.phase, .unavailable)
        XCTAssertTrue(rig.model.wantsKeyboard, "the reason shows and the keyboard opens")
        XCTAssertTrue(rig.transcriber.starts.isEmpty)
        let text = await rig.model.release()
        XCTAssertNil(text)

        // A recognizer that fails to start is unavailable too, never a stuck mic.
        let failing = makeRig()
        failing.transcriber.startError = URLError(.notConnectedToInternet)
        await failing.model.press()
        XCTAssertEqual(failing.model.phase, .unavailable)
        XCTAssertTrue(failing.model.wantsKeyboard)

        // So does one that fails before any word.
        let dropped = makeRig()
        await dropped.model.press()
        dropped.transcriber.fail(URLError(.networkConnectionLost))
        await waitForPhase(dropped.model, .unavailable)
        XCTAssertTrue(dropped.model.wantsKeyboard)
        dropped.model.dismiss()
        XCTAssertEqual(dropped.model.phase, .idle)
    }

    func testFirstWordLatencyRecorded() async throws {
        let rig = makeRig()
        await rig.model.press()
        rig.clock.advance(by: .milliseconds(40))
        rig.transcriber.say(" ")
        // A blank update is not a word.
        await waitForPhase(rig.model, .listening(text: " "))
        XCTAssertNil(rig.model.firstWordLatency)
        rig.clock.advance(by: .milliseconds(140))
        rig.transcriber.say("chạy")
        await waitForPhase(rig.model, .listening(text: "chạy"))
        XCTAssertEqual(rig.model.firstWordLatency, .milliseconds(180))
        rig.clock.advance(by: .milliseconds(500))
        rig.transcriber.say("chạy test")
        await waitForPhase(rig.model, .listening(text: "chạy test"))
        XCTAssertEqual(rig.model.firstWordLatency, .milliseconds(180), "only the first word counts")

        let summary = try XCTUnwrap(rig.latency.summary(.firstWord))
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.p50, .milliseconds(180))
        _ = await rig.model.release()

        // Each press measures again.
        await rig.model.press()
        XCTAssertNil(rig.model.firstWordLatency)
        rig.clock.advance(by: .milliseconds(90))
        rig.transcriber.say("push")
        await waitForPhase(rig.model, .listening(text: "push"))
        XCTAssertEqual(rig.model.firstWordLatency, .milliseconds(90))
        XCTAssertEqual(rig.latency.summary(.firstWord)?.count, 2)
    }

    func testDictationStopsAtByteLimit() async throws {
        let rig = makeRig()
        await rig.model.press()
        let start = String(repeating: "chạy test rồi push. ", count: 600)
        XCTAssertLessThan(start.utf8.count, ComposerValidation.maxBytes)
        rig.transcriber.say(start)
        await waitForPhase(rig.model, .listening(text: start))
        XCTAssertFalse(rig.model.limitReached)

        // Ten minutes of talking: far past 16 384 bytes, ending in multi-byte letters.
        let long = start + String(repeating: "giữ route v1, đừng xoá. ", count: 600)
        rig.transcriber.say(long)
        let stopped = await eventually { rig.model.limitReached }
        XCTAssertTrue(stopped)
        let cancelled = await eventually { rig.transcriber.cancelCalls == 1 }
        XCTAssertTrue(cancelled, "listening stops at the limit")
        guard case let .listening(kept) = rig.model.phase else {
            return XCTFail("the kept words stay on screen, not \(rig.model.phase)")
        }
        XCTAssertLessThanOrEqual(kept.utf8.count, ComposerValidation.maxBytes)
        XCTAssertGreaterThan(kept.utf8.count, ComposerValidation.maxBytes - 4)
        XCTAssertTrue(long.hasPrefix(kept))
        XCTAssertFalse(rig.transcriber.isRunning, "nothing more is heard")

        let released = await rig.model.release()
        let text = try XCTUnwrap(released)
        XCTAssertEqual(text, kept.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(ComposerValidation(text), .ok(text), "the kept words can be sent")
        XCTAssertEqual(rig.transcriber.finishCalls, 0)
        XCTAssertTrue(rig.model.limitReached, "the flag stays for the screen to say why")

        // A final text past a smaller limit (a question's answer) is cut the same way.
        let answer = makeRig(maxBytes: 1024)
        await answer.model.press()
        answer.transcriber.finalText = String(repeating: "ệ", count: 400)
        let answered = await answer.model.release()
        let cut = try XCTUnwrap(answered)
        XCTAssertEqual(cut.utf8.count, 1023)
        XCTAssertTrue(answer.model.limitReached)
    }

    func testReleaseWhileStartingStopsCleanly() async {
        let rig = makeRig()
        rig.transcriber.holdStarts()
        let press = Task { await rig.model.press() }
        let held = await eventually { rig.transcriber.startsWaiting == 1 }
        XCTAssertTrue(held)
        let text = await rig.model.release()
        XCTAssertNil(text)
        XCTAssertEqual(rig.model.phase, .idle)
        rig.transcriber.releaseStarts()
        await press.value
        XCTAssertEqual(rig.model.phase, .idle, "the late start is not shown")
        let cancelled = await eventually { rig.transcriber.cancelCalls == 1 }
        XCTAssertTrue(cancelled, "the recognizer that started late is stopped")
    }

    func testCancelStopsListeningWhenTheScreenGoes() async {
        let rig = makeRig()
        await rig.model.press()
        rig.transcriber.say("đang nói dở")
        await waitForPhase(rig.model, .listening(text: "đang nói dở"))
        await rig.model.cancel()
        XCTAssertEqual(rig.model.phase, .idle)
        XCTAssertEqual(rig.transcriber.cancelCalls, 1)
        XCTAssertFalse(rig.transcriber.isRunning)
        let text = await rig.model.release()
        XCTAssertNil(text, "nothing is sent after the screen went away")

        // Nothing listening: nothing to stop.
        await rig.model.cancel()
        XCTAssertEqual(rig.transcriber.cancelCalls, 1)
    }

    // MARK: - The microphone is always released

    func testStreamEndingByItselfReleasesTheMic() async {
        // A natural end (a server session's time limit): the words stay, the recognizer is stopped.
        let rig = makeRig()
        await rig.model.press()
        let run = rig.transcriber.starts.last?.run
        rig.transcriber.say("sửa CI đỏ")
        await waitForPhase(rig.model, .listening(text: "sửa CI đỏ"))
        rig.transcriber.endStream()
        let released = await eventually { rig.transcriber.cancelledRuns == [run].compactMap { $0 } }
        XCTAssertTrue(released, "the transcriber is cancelled, so it stops the microphone: \(rig.transcriber.cancelledRuns)")
        XCTAssertEqual(rig.model.phase, .listening(text: "sửa CI đỏ"), "the words stay until the finger lifts")
        let text = await rig.model.release()
        XCTAssertEqual(text, "sửa CI đỏ")
        XCTAssertEqual(rig.transcriber.finishCalls, 0)

        // An error before any word: unavailable, and the microphone is released too.
        let failed = makeRig()
        await failed.model.press()
        let failedRun = failed.transcriber.starts.last?.run
        failed.transcriber.fail(URLError(.networkConnectionLost))
        await waitForPhase(failed.model, .unavailable)
        let stopped = await eventually { failed.transcriber.cancelledRuns == [failedRun].compactMap { $0 } }
        XCTAssertTrue(stopped)
    }

    func testTypeInsteadCancelsTheDictation() async {
        let rig = makeRig()
        await rig.model.press()
        rig.transcriber.say("đang nói")
        await waitForPhase(rig.model, .listening(text: "đang nói"))
        await rig.model.typeInstead()
        XCTAssertEqual(rig.model.phase, .idle)
        XCTAssertEqual(rig.transcriber.cancelCalls, 1)
        XCTAssertFalse(rig.transcriber.isRunning)
        let text = await rig.model.release()
        XCTAssertNil(text, "nothing heard before the keyboard opened is sent later")

        // Nothing listening: nothing to cancel; a "can't listen" notice is left for typing to clear.
        let denied = makeRig(microphone: false)
        await denied.model.press()
        await denied.model.typeInstead()
        XCTAssertEqual(denied.transcriber.cancelCalls, 0)
        XCTAssertEqual(denied.model.phase, .denied(.microphone))
    }

    func testLateStartCancelNeverStopsTheNextPress() async {
        let rig = makeRig()
        rig.transcriber.holdStarts()
        // A quick tap: its start is still held when the finger lifts.
        let first = Task { await rig.model.press() }
        let firstHeld = await eventually { rig.transcriber.startsWaiting == 1 }
        XCTAssertTrue(firstHeld)
        let none = await rig.model.release()
        XCTAssertNil(none)
        // A hold right after: its start is held too.
        let second = Task { await rig.model.press() }
        let secondHeld = await eventually { rig.transcriber.startsWaiting == 2 }
        XCTAssertTrue(secondHeld)
        rig.transcriber.releaseStarts()
        await first.value
        await second.value

        let runs = rig.transcriber.starts.map(\.run)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(rig.transcriber.cancelledRuns, [runs[0]], "only the tap's run is stopped")
        rig.transcriber.say("tạo PR")
        await waitForPhase(rig.model, .listening(text: "tạo PR"))
        rig.transcriber.finalText = "Tạo PR."
        let text = await rig.model.release()
        XCTAssertEqual(text, "Tạo PR.")
    }

    func testStartReleasedWhileStartingNeverTakesTheMic() async {
        let rig = makeRig()
        rig.transcriber.holdStarts()
        let press = Task { await rig.model.press() }
        let held = await eventually { rig.transcriber.startsWaiting == 1 }
        XCTAssertTrue(held)
        let run = rig.transcriber.starts[0].run
        let none = await rig.model.release()
        XCTAssertNil(none)
        XCTAssertEqual(rig.transcriber.cancelledRuns, [run], "the release cancels the run while it still starts")

        rig.transcriber.releaseStarts()
        await press.value
        XCTAssertFalse(rig.transcriber.grantedRuns.contains(run), "it never took the microphone, not even briefly")
        XCTAssertNil(rig.transcriber.activeRun)
        XCTAssertEqual(rig.model.phase, .idle)
    }

    func testStaleStartFinishingSecondNeverTakesTheMic() async {
        let rig = makeRig()
        rig.transcriber.holdStarts()
        // A quick tap, released while its start is held.
        let tap = Task { await rig.model.press() }
        let tapHeld = await eventually { rig.transcriber.startsWaiting == 1 }
        XCTAssertTrue(tapHeld)
        _ = await rig.model.release()
        // A hold right after.
        let hold = Task { await rig.model.press() }
        let holdHeld = await eventually { rig.transcriber.startsWaiting == 2 }
        XCTAssertTrue(holdHeld)
        let runs = rig.transcriber.starts.map(\.run)

        // The newer start finishes first, the stale one second.
        rig.transcriber.releaseStart(of: runs[1])
        await hold.value
        XCTAssertEqual(rig.transcriber.activeRun, runs[1])
        rig.transcriber.releaseStart(of: runs[0])
        await tap.value

        XCTAssertEqual(rig.transcriber.grantedRuns, [runs[1]], "the stale start never took the microphone")
        XCTAssertEqual(rig.transcriber.activeRun, runs[1], "and never tore down the newer run")
        XCTAssertTrue(rig.transcriber.isRunning)
        rig.transcriber.say("tạo PR")
        await waitForPhase(rig.model, .listening(text: "tạo PR"))
        rig.transcriber.finalText = "Tạo PR."
        let text = await rig.model.release()
        XCTAssertEqual(text, "Tạo PR.")
    }

    func testNoFirstWordSampleAfterAPermissionPrompt() async {
        let rig = makeRig()
        rig.permissions.promptPending = true
        await rig.model.press()
        rig.clock.advance(by: .seconds(4))
        rig.transcriber.say("chạy")
        await waitForPhase(rig.model, .listening(text: "chạy"))
        XCTAssertNil(rig.model.firstWordLatency, "the prompt's time is not speech latency")
        XCTAssertNil(rig.latency.summary(.firstWord))
        _ = await rig.model.release()

        // The next press, with nothing to ask, is measured.
        rig.permissions.promptPending = false
        await rig.model.press()
        rig.clock.advance(by: .milliseconds(120))
        rig.transcriber.say("push")
        await waitForPhase(rig.model, .listening(text: "push"))
        XCTAssertEqual(rig.model.firstWordLatency, .milliseconds(120))
        XCTAssertEqual(rig.latency.summary(.firstWord)?.count, 1)
    }

    func testLimitCutDictationIsForReviewNotSending() async throws {
        let rig = makeRig(maxBytes: 64)
        await rig.model.press()
        rig.transcriber.say("chạy test")
        await waitForPhase(rig.model, .listening(text: "chạy test"))
        let first = await rig.model.release()
        let whole = try XCTUnwrap(first)
        XCTAssertEqual(rig.model.outcome(for: whole), .complete("chạy test"))

        await rig.model.press()
        rig.transcriber.say(String(repeating: "giữ route v1 ", count: 10))
        let stopped = await eventually { rig.model.limitReached }
        XCTAssertTrue(stopped)
        let second = await rig.model.release()
        let cut = try XCTUnwrap(second)
        XCTAssertEqual(rig.model.outcome(for: cut), .cutAtLimit(cut), "read it in the field first; no success haptic")
    }

    func testContextualStringsAddTermsToWorkspaces() {
        let strings = VoiceInputModel.contextualStrings(workspaceTitles: ["shellx", "web", "shellx", " ", "PR"])
        XCTAssertEqual(Array(strings.prefix(2)), ["shellx", "web"])
        for term in ["PR", "CI", "push", "pull request", "branch", "merge", "deploy", "commit", "Claude"] {
            XCTAssertEqual(strings.filter { $0 == term }.count, 1, term)
        }
        XCTAssertEqual(strings.count, 11)
    }
}
