import AVFoundation
import Foundation
import ShellXAppCore
import Speech

/// Dictation with `SFSpeechRecognizer` (iOS 17 and later): partial results as the user talks, on
/// the iPhone when the recognizer supports the language there, otherwise on Apple's servers
/// (Settings › Voice says so). Never logs what it hears.
///
/// Runs go through the `SpeechRunSlot` shared with the other transcribers of the microphone: the
/// newest start takes the microphone (tearing down the run it replaces); a start that was overtaken
/// or cancelled while it started never does. `finish` and `cancel` act on the run they name only, and
/// every audio stop names its run, so an old run can never stop a newer capture. A run that ends by
/// itself (a final result, an error, a server time limit) gives the microphone back at once.
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
        var task: (any RecognitionTask)?
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

    /// Starts the recognition task of a request (the system's in the app; tests record and fake it).
    typealias TaskStarter = @Sendable (
        SFSpeechRecognizer, SFSpeechAudioBufferRecognitionRequest,
        @escaping @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void
    ) -> any RecognitionTask

    static let systemTasks: TaskStarter = { recognizer, request, handler in
        recognizer.recognitionTask(with: request, resultHandler: handler)
    }

    private let audio: AudioCapture
    private let slot: SpeechRunSlot
    private let startTask: TaskStarter
    private let lock = NSLock()

    init(audio: AudioCapture, slot: SpeechRunSlot, startTask: @escaping TaskStarter = LegacyTranscriber.systemTasks) {
        self.audio = audio
        self.slot = slot
        self.startTask = startTask
    }

    func start(run id: SpeechRunID, locale: Locale, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>
    {
        slot.begin(id)
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
        let handlers = SpeechRunSlot.Handlers(
            finish: { [weak self] in await self?.finish(run) ?? "" },
            teardown: { [weak self] in self?.tearDown(run) })
        switch slot.claim(id, handlers) {
        case .refused:
            // Overtaken or cancelled while starting: never takes the microphone.
            end(run, error: nil)
            return stream
        case let .granted(replaced):
            await replaced?.teardown()
        }
        let task = startTask(recognizer, request) { [weak self] result, error in
            self?.handle(run, text: result?.bestTranscription.formattedString, isFinal: result?.isFinal ?? false, error: error)
        }
        lock.withLock { run.task = task }
        do {
            let slot = self.slot
            try audio.start(owner: id, stillWanted: { slot.isActive(id) }) { buffer in run.request.append(buffer) }
        } catch {
            _ = slot.ended(id)
            tearDown(run)
            throw error
        }
        return stream
    }

    func finish(run id: SpeechRunID) async -> String {
        await slot.takeForFinish(id)?.finish() ?? ""
    }

    func cancel(run id: SpeechRunID) async {
        await slot.cancel(id)?.teardown()
    }

    // MARK: - Private

    /// Ends the audio, then waits for the final result (at most `finalResultTimeout`).
    private func finish(_ run: Run) async -> String {
        audio.stop(owner: run.id)
        run.request.endAudio()
        return await withCheckedContinuation { (waiter: CheckedContinuation<String, Never>) in
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
    }

    /// Stops `run`'s audio and recognition task and ends its stream.
    private func tearDown(_ run: Run) {
        audio.stop(owner: run.id)
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
        // Ended by itself (a server session's time limit, an error) while it held the microphone:
        // give it back. Only this run's capture is stopped, never a newer one.
        if slot.ended(run.id) { audio.stop(owner: run.id) }
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
