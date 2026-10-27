import Foundation
import ShellXAppCore

/// A `SpeechTranscribing` the test drives. `say(_:)` sends the words heard so far on the newest
/// run; `fail(_:)` and `endStream()` end it by themselves (an error, a time limit); `finalText` is
/// what `finish` returns (by default the last words said). Every run has its own stream: `finish`
/// and `cancel` end only the run they name. Records each start, finish and cancel, and can hold
/// starts until the test releases them.
public final class FakeTranscriber: SpeechTranscribing, @unchecked Sendable {
    /// One `start` call.
    public struct Start: Equatable, Sendable {
        public var run: SpeechRunID
        public var locale: Locale
        public var contextualStrings: [String]
    }

    private let lock = NSLock()
    private var streams: [SpeechRunID: AsyncThrowingStream<String, any Error>.Continuation] = [:]
    /// The newest run started (the one `say` speaks to).
    private var newest: SpeechRunID?
    private var lastSaid = ""
    private var finalAnswer: String?
    private var storedStartError: (any Error)?
    private var startList: [Start] = []
    private var finishCount = 0
    private var cancelList: [SpeechRunID] = []
    private var holding = false
    private var heldStarts: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Every start, in order.
    public var starts: [Start] { lock.withLock { startList } }
    public var finishCalls: Int { lock.withLock { finishCount } }
    /// Every `cancel`, whatever run it named.
    public var cancelCalls: Int { lock.withLock { cancelList.count } }
    /// The runs `cancel` named, in order.
    public var cancelledRuns: [SpeechRunID] { lock.withLock { cancelList } }
    /// The newest run's stream is open: started, and not finished, cancelled or ended.
    public var isRunning: Bool { lock.withLock { newest.map { streams[$0] != nil } ?? false } }
    /// Starts held by `holdStarts()`.
    public var startsWaiting: Int { lock.withLock { heldStarts.count } }

    /// What `finish` returns; nil returns the last words said.
    public var finalText: String? {
        get { lock.withLock { finalAnswer } }
        set { lock.withLock { finalAnswer = newValue } }
    }

    /// When set, `start` throws it.
    public var startError: (any Error)? {
        get { lock.withLock { storedStartError } }
        set { lock.withLock { storedStartError = newValue } }
    }

    /// Holds every later `start` (after it is recorded) until `releaseStarts()`.
    public func holdStarts() {
        lock.withLock { holding = true }
    }

    public func releaseStarts() {
        let held = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { heldStarts = [] }
            return heldStarts
        }
        for start in held { start.resume() }
    }

    /// Sends `text` as everything the newest run heard so far.
    public func say(_ text: String) {
        let open = lock.withLock { () -> AsyncThrowingStream<String, any Error>.Continuation? in
            guard let newest, let current = streams[newest] else { return nil }
            lastSaid = text
            return current
        }
        open?.yield(text)
    }

    /// Ends the newest run's stream with `error`, as a recognizer that fails does.
    public func fail(_ error: any Error) {
        takeNewest()?.finish(throwing: error)
    }

    /// Ends the newest run's stream without an error, as a recognizer that reaches its time limit does.
    public func endStream() {
        takeNewest()?.finish()
    }

    private func takeNewest() -> AsyncThrowingStream<String, any Error>.Continuation? {
        lock.withLock {
            guard let newest else { return nil }
            return streams.removeValue(forKey: newest)
        }
    }

    // MARK: - SpeechTranscribing

    public func start(run: SpeechRunID, locale: Locale, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>
    {
        let hold = lock.withLock { () -> Bool in
            startList.append(Start(run: run, locale: locale, contextualStrings: contextualStrings))
            newest = run
            return holding
        }
        if hold {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    guard holding else { return true }
                    heldStarts.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        if let error = startError { throw error }
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        lock.withLock {
            streams[run] = continuation
            if newest == run { lastSaid = "" }
        }
        return stream
    }

    public func finish(run: SpeechRunID) async -> String {
        let (continuation, text) = lock.withLock { () -> (AsyncThrowingStream<String, any Error>.Continuation?, String) in
            finishCount += 1
            return (streams.removeValue(forKey: run), finalAnswer ?? lastSaid)
        }
        continuation?.finish()
        return text
    }

    public func cancel(run: SpeechRunID) async {
        let continuation = lock.withLock { () -> AsyncThrowingStream<String, any Error>.Continuation? in
            cancelList.append(run)
            return streams.removeValue(forKey: run)
        }
        continuation?.finish()
    }
}
