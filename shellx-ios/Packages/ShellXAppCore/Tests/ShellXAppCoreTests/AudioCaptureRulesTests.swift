import XCTest

@testable import ShellXAppCore

/// Two rules of the microphone capture: a route change stops a dictation only when the input it used
/// went away (not when AirPods or a speaker used for output leave), and the level bar is updated
/// about twenty times a second whatever the size of the buffers the system hands over.
final class AudioCaptureRulesTests: XCTestCase {
    func testOutputOnlyDeviceLeavingKeepsTheDictation() {
        // AirPods used for output leave; the built-in microphone stays the input.
        XCTAssertFalse(AudioInputRoute.inputLost(
            previousInputs: ["Built-In Microphone"], currentInputs: ["Built-In Microphone"], inputAvailable: true))
        // A speaker with no input at all.
        XCTAssertFalse(AudioInputRoute.inputLost(previousInputs: [], currentInputs: [], inputAvailable: true))
    }

    func testInputThatWentAwayStopsTheDictation() {
        // A headset whose microphone was the input is unplugged.
        XCTAssertTrue(AudioInputRoute.inputLost(
            previousInputs: ["Headset Microphone"], currentInputs: ["Built-In Microphone"], inputAvailable: true))
        // No input left at all.
        XCTAssertTrue(AudioInputRoute.inputLost(previousInputs: [], currentInputs: [], inputAvailable: false))
    }

    func testSmallBuffersReportAboutTwentyTimesASecond() {
        var throttle = AudioLevelThrottle()
        var reports = 0
        // One second of 1024-frame buffers at 48 kHz.
        for _ in 0..<47 where throttle.take(frames: 1024, sampleRate: 48_000) { reports += 1 }
        XCTAssertEqual(reports, 20, accuracy: 1)
    }

    func testLargeBuffersReportEveryBuffer() {
        var throttle = AudioLevelThrottle()
        var reports = 0
        // One second of 100 ms buffers (what a device's tap often delivers): every one is reported.
        for _ in 0..<10 where throttle.take(frames: 4800, sampleRate: 48_000) { reports += 1 }
        XCTAssertEqual(reports, 10)
        // Odd sizes and rates keep the same pace.
        var odd = AudioLevelThrottle()
        var oddReports = 0
        for _ in 0..<100 where odd.take(frames: 441, sampleRate: 44_100) { oddReports += 1 }
        XCTAssertEqual(oddReports, 20, accuracy: 1)
        XCTAssertFalse(odd.take(frames: 0, sampleRate: 0), "an empty buffer reports nothing")
    }
}
