import AVFoundation
import Foundation
import ShellXAppCore
import Speech

/// Dictation with `SFSpeechRecognizer` (iOS 17 and later): partial results as the user talks, on
/// the iPhone when the recognizer supports the language there, otherwise on Apple's servers
/// (Settings › Voice says so). Never logs what it hears.
///
/// One run at a time: starting a run tears down any other; `finish` and `cancel` act on the run they
/// name only. A run that ends by itself (a final result, an error, a server time limit) gives the
/// microphone back at once.
final class LegacyTranscriber: SpeechTranscribing, @unchecked Sendable {
    enum Failure: Error {
        /// No recognizer for the language, or it is not available now (no network, nothing on device).
        case unavailable
    }

    /// How long `finish` waits for the final result after the audio ends.
    static let finalResultTimeout: Duration = .milliseconds(1500)

    /// One dictation: the recognizer, the request, its task, and the stream of what was heard.
    private final class Run: @unchecked Sendable {
        let id: SpeechRunID
        let recognizer: SFSpeechRecognizer
        let request: SFSpeechAudioBufferRecognitionRequest
        let continuation: AsyncThrowingStream<String, any Error>.Continuation
        /// The fields below are read and written under `LegacyTranscriber.lock`.
        var task: SFSpeechRecognitionTask?
        var latest = ""
        var ended = false
        var finalWaiter: CheckedContinuation<String, Never>?

        init(
            id: SpeechRunID, recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
            continuation: AsyncThrowingStream<String, any Error>.Continuation
        ) {
            self.id = id
            self.recognizer = recognizer
            self.request = request
            self.continuation = continuation
        }
    }

    private let audio: AudioCapture
    private let lock = NSLock()
    private var current: Run?

    init(audio: AudioCapture) {
        self.audio = audio
    }

    func start(run id: SpeechRunID, locale: Locale, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>
    {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.unavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On the iPhone whenever it can; otherwise Apple's servers, as Settings discloses.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation

        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let run = Run(id: id, recognizer: recognizer, request: request, continuation: continuation)
        // This run replaces any other: the other one is torn down, never left holding the mic.
        let previous = lock.withLock { () -> Run? in
            defer { current = run }
            return current
        }
        if let previous { tearDown(previous) }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(run, text: result?.bestTranscription.formattedString, isFinal: result?.isFinal ?? false, error: error)
        }
        lock.withLock { run.task = task }
        do {
            _ = try audio.start { buffer in run.request.append(buffer) }
        } catch {
            tearDown(run)
            throw error
        }
        return stream
    }

    func finish(run id: SpeechRunID) async -> String {
        guard let run = lock.withLock({ current?.id == id ? current : nil }) else { return "" }
        audio.stop()
        run.request.endAudio()
        let text = await withCheckedContinuation { (waiter: CheckedContinuation<String, Never>) in
            let ready = lock.withLock { () -> String? in
                if run.ended { return run.latest }
                run.finalWaiter = waiter
                return nil
            }
            if let ready {
                waiter.resume(returning: ready)
                return
            }
            // Some results never become final (no speech at all): stop waiting after a while, and
            // stop the recognition task, so a server session does not linger.
            Task { [weak self] in
                try? await Task.sleep(for: Self.finalResultTimeout)
                guard let self else { return }
                self.lock.withLock { run.task }?.cancel()
                self.end(run, error: nil)
            }
        }
        lock.withLock { if current === run { current = nil } }
        return text
    }

    func cancel(run id: SpeechRunID) async {
        let run = lock.withLock { () -> Run? in
            guard let current, current.id == id else { return nil }
            self.current = nil
            return current
        }
        if let run { tearDown(run) }
    }

    // MARK: - Private

    /// Stops `run`'s audio and recognition task and ends its stream.
    private func tearDown(_ run: Run) {
        audio.stop()
        lock.withLock { run.task }?.cancel()
        end(run, error: nil)
    }

    private func handle(_ run: Run, text: String?, isFinal: Bool, error: (any Error)?) {
        if let text {
            let fresh = lock.withLock { () -> Bool in
                guard !run.ended else { return false }
                run.latest = text
                return true
            }
            if fresh { run.continuation.yield(text) }
        }
        guard isFinal || error != nil else { return }
        // An error after some words (often "no speech" at the very end) keeps the words.
        let hadWords = lock.withLock { !run.latest.isEmpty }
        end(run, error: hadWords ? nil : error)
        // Ended by itself (a server session's time limit, an error): give the microphone back.
        if lock.withLock({ current === run }) { audio.stop() }
    }

    /// Ends `run` once: finishes its stream and answers a waiting `finish`.
    private func end(_ run: Run, error: (any Error)?) {
        let outcome = lock.withLock { () -> (first: Bool, waiter: CheckedContinuation<String, Never>?, text: String) in
            guard !run.ended else { return (false, nil, "") }
            run.ended = true
            let waiter = run.finalWaiter
            run.finalWaiter = nil
            return (true, waiter, run.latest)
        }
        guard outcome.first else { return }
        if let error {
            run.continuation.finish(throwing: error)
        } else {
            run.continuation.finish()
        }
        outcome.waiter?.resume(returning: outcome.text)
    }
}
