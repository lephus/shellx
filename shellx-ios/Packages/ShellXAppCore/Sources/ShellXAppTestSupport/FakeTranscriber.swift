import Foundation
import ShellXAppCore

/// A `SpeechTranscribing` the test drives, following the real transcribers' rule through a
/// `SpeechRunSlot`: one run holds the microphone; the newest start wins; a start that was overtaken,
/// or whose run was cancelled while it started, never takes the microphone; a granted start tears
/// down the run it replaces (its stream ends).
///
/// `say(_:)` sends the words heard so far on the run that holds the microphone; `fail(_:)` and
/// `endStream()` end it by themselves (an error, a time limit); `finalText` is what `finish` returns
/// (by default the last words said). Records each start, granted claim, finish and cancel, and can
/// hold starts until the test releases them, all at once or one run at a time.
public final class FakeTranscriber: SpeechTranscribing, @unchecked Sendable {
    /// One `start` call.
    public struct Start: Equatable, Sendable {
        public var run: SpeechRunID
        public var locale: Locale
        public var contextualStrings: [String]
    }

    private let slot: SpeechRunSlot
    private let lock = NSLock()
    private var streams: [SpeechRunID: AsyncThrowingStream<String, any Error>.Continuation] = [:]
    private var lastSaid = ""
    private var finalAnswer: String?
    private var storedStartError: (any Error)?
    private var startList: [Start] = []
    private var grantList: [SpeechRunID] = []
    private var finishCount = 0
    private var cancelList: [SpeechRunID] = []
    private var holding = false
    private var heldStarts: [(run: SpeechRunID, continuation: CheckedContinuation<Void, Never>)] = []

    /// `slot` is shared with other transcribers of the same microphone (a fallback, for instance).
    public init(slot: SpeechRunSlot = SpeechRunSlot()) {
        self.slot = slot
    }

    /// Every start, in order.
    public var starts: [Start] { lock.withLock { startList } }
    /// The runs whose start took the microphone, in order.
    public var grantedRuns: [SpeechRunID] { lock.withLock { grantList } }
    public var finishCalls: Int { lock.withLock { finishCount } }
    /// Every `cancel`, whatever run it named.
    public var cancelCalls: Int { lock.withLock { cancelList.count } }
    /// The runs `cancel` named, in order.
    public var cancelledRuns: [SpeechRunID] { lock.withLock { cancelList } }
    /// The run that holds the microphone.
    public var activeRun: SpeechRunID? { slot.active }
    /// A run holds the microphone and its stream is open.
    public var isRunning: Bool {
        guard let active = slot.active else { return false }
        return lock.withLock { streams[active] != nil }
    }
    /// Starts held by `holdStarts()`.
    public var startsWaiting: Int { lock.withLock { heldStarts.count } }

    /// What `finish` returns; nil returns the last words said.
    public var finalText: String? {
        get { lock.withLock { finalAnswer } }
        set { lock.withLock { finalAnswer = newValue } }
    }

    /// When set, `start` throws it (before taking the microphone).
    public var startError: (any Error)? {
        get { lock.withLock { storedStartError } }
        set { lock.withLock { storedStartError = newValue } }
    }

    /// Holds every later `start` (after it is recorded and has begun) until it is released.
    public func holdStarts() {
        lock.withLock { holding = true }
    }

    /// Lets every held start through, oldest first, and stops holding.
    public func releaseStarts() {
        let held = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { heldStarts = [] }
            return heldStarts.map(\.continuation)
        }
        for start in held { start.resume() }
    }

    /// Lets the held start of `run` through; the others stay held.
    public func releaseStart(of run: SpeechRunID) {
        let held = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            guard let index = heldStarts.firstIndex(where: { $0.run == run }) else { return nil }
            return heldStarts.remove(at: index).continuation
        }
        held?.resume()
    }

    /// Sends `text` as everything the run holding the microphone heard so far.
    public func say(_ text: String) {
        let open = lock.withLock { () -> AsyncThrowingStream<String, any Error>.Continuation? in
            guard let active = slot.active, let current = streams[active] else { return nil }
            lastSaid = text
            return current
        }
        open?.yield(text)
    }

    /// Ends the active run's stream with `error`, as a recognizer that fails does.
    public func fail(_ error: any Error) {
        endActive()?.finish(throwing: error)
    }

    /// Ends the active run's stream without an error, as a recognizer that reaches its time limit does.
    public func endStream() {
        endActive()?.finish()
    }

    private func endActive() -> AsyncThrowingStream<String, any Error>.Continuation? {
        guard let active = slot.active, slot.ended(active) else { return nil }
        return lock.withLock { streams.removeValue(forKey: active) }
    }

    private func close(_ run: SpeechRunID) {
        let continuation = lock.withLock { streams.removeValue(forKey: run) }
        continuation?.finish()
    }

    // MARK: - SpeechTranscribing

    public func start(run: SpeechRunID, locale: Locale, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>
    {
        slot.begin(run)
        let hold = lock.withLock { () -> Bool in
            startList.append(Start(run: run, locale: locale, contextualStrings: contextualStrings))
            return holding
        }
        if hold {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    guard holding else { return true }
                    heldStarts.append((run, continuation))
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        if let error = startError { throw error }
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        lock.withLock { streams[run] = continuation }
        let handlers = SpeechRunSlot.Handlers(
            finish: { [weak self] in
                guard let self else { return "" }
                let text = self.lock.withLock { self.finalAnswer ?? self.lastSaid }
                self.close(run)
                return text
            },
            teardown: { [weak self] in self?.close(run) })
        switch slot.claim(run, handlers) {
        case .refused:
            // Overtaken or cancelled while starting: never takes the microphone.
            close(run)
        case let .granted(replaced):
            lock.withLock {
                grantList.append(run)
                lastSaid = ""
            }
            await replaced?.teardown()
        }
        return stream
    }

    public func finish(run: SpeechRunID) async -> String {
        lock.withLock { finishCount += 1 }
        return await slot.takeForFinish(run)?.finish() ?? ""
    }

    public func cancel(run: SpeechRunID) async {
        lock.withLock { cancelList.append(run) }
        await slot.cancel(run)?.teardown()
    }
}
