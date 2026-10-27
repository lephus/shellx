import AVFoundation
import Foundation
import ShellXAppCore
import Speech

/// Dictation with `SFSpeechRecognizer` (iOS 17 and later): partial results as the user talks, on
/// the iPhone when the recognizer supports the language there, otherwise on Apple's servers
/// (Settings › Voice says so). Never logs what it hears.
final class LegacyTranscriber: SpeechTranscribing, @unchecked Sendable {
    enum Failure: Error {
        /// No recognizer for the language, or it is not available now (no network, nothing on device).
        case unavailable
    }

    /// How long `finish()` waits for the final result after the audio ends.
    static let finalResultTimeout: Duration = .milliseconds(1500)

    /// One dictation: the recognizer, the request, its task, and the stream of what was heard.
    private final class Run: @unchecked Sendable {
        let recognizer: SFSpeechRecognizer
        let request: SFSpeechAudioBufferRecognitionRequest
        let continuation: AsyncThrowingStream<String, any Error>.Continuation
        var task: SFSpeechRecognitionTask?
        var latest = ""
        var ended = false
        var finalWaiter: CheckedContinuation<String, Never>?

        init(
            recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
            continuation: AsyncThrowingStream<String, any Error>.Continuation
        ) {
            self.recognizer = recognizer
            self.request = request
            self.continuation = continuation
        }
    }

    private let audio: AudioCapture
    private let lock = NSLock()
    private var run: Run?

    init(audio: AudioCapture) {
        self.audio = audio
    }

    func start(locale: Locale, contextualStrings: [String]) async throws -> AsyncThrowingStream<String, any Error> {
        await cancel()
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
        let run = Run(recognizer: recognizer, request: request, continuation: continuation)
        lock.withLock { self.run = run }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(run, text: result?.bestTranscription.formattedString, isFinal: result?.isFinal ?? false, error: error)
        }
        lock.withLock { run.task = task }
        do {
            _ = try audio.start { buffer in run.request.append(buffer) }
        } catch {
            task.cancel()
            end(run, error: error)
            throw error
        }
        return stream
    }

    func finish() async -> String {
        guard let run = lock.withLock({ self.run }) else { return "" }
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
            // Some results never become final (no speech at all): stop waiting after a while.
            Task { [weak self] in
                try? await Task.sleep(for: Self.finalResultTimeout)
                self?.end(run, error: nil)
            }
        }
        lock.withLock { if self.run === run { self.run = nil } }
        return text
    }

    func cancel() async {
        let current = lock.withLock { () -> Run? in
            defer { self.run = nil }
            return self.run
        }
        guard let current else { return }
        audio.stop()
        current.task?.cancel()
        end(current, error: nil)
    }

    // MARK: - Private

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
        if lock.withLock({ self.run === run }) { audio.stop() }
    }

    /// Ends `run` once: finishes its stream and answers a waiting `finish()`.
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
