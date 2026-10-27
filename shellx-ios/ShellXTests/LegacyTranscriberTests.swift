import ShellXAppCore
import Speech
import XCTest
@testable import ShellX

/// `SFSpeechRecognizer` dictation: a run torn down while it starts (released, or taken over) never
/// leaves its recognition task running, which would be a lingering server session when the
/// language cannot run on the iPhone.
@MainActor
final class LegacyTranscriberTests: XCTestCase {
    /// Stands in for the system's recognition tasks and records each one.
    private final class Tasks: @unchecked Sendable {
        final class Task: RecognitionTask {
            private let lock = NSLock()
            private var wasCancelled = false
            var cancelled: Bool { lock.withLock { wasCancelled } }
            func cancel() { lock.withLock { wasCancelled = true } }
        }

        private let lock = NSLock()
        private var list: [Task] = []
        var created: [Task] { lock.withLock { list } }

        var starter: LegacyTranscriber.TaskStarter {
            { [self] _, _, _ in
                let task = Task()
                lock.withLock { list.append(task) }
                return task
            }
        }
    }

    func testTeardownDuringStartCancelsTheRecognitionTask() async throws {
        let locale = Locale(identifier: "en-US")
        try XCTSkipUnless(SFSpeechRecognizer(locale: locale)?.isAvailable ?? false, "no en-US recognizer here")
        let slot = SpeechRunSlot()
        let tasks = Tasks()
        let legacy = LegacyTranscriber(audio: AudioCapture(meter: AudioLevelMeter()), slot: slot, startTask: tasks.starter)

        // A live run holds the microphone. Replacing it takes a moment, and in that moment the new
        // run is torn down too (its press was released).
        let live = SpeechRunID()
        let newer = SpeechRunID()
        slot.begin(live)
        _ = slot.claim(live, SpeechRunSlot.Handlers(finish: { "" }, teardown: { await legacy.cancel(run: newer) }))

        let stream = try await legacy.start(run: newer, locale: locale, contextualStrings: [])
        XCTAssertNil(slot.active, "nothing holds the microphone")
        XCTAssertEqual(tasks.created.count, 1)
        XCTAssertTrue(tasks.created.first?.cancelled ?? false, "the recognition task does not outlive its run")
        var words: [String] = []
        for try await text in stream { words.append(text) }
        XCTAssertTrue(words.isEmpty, "and the run's stream has ended")
    }
}
