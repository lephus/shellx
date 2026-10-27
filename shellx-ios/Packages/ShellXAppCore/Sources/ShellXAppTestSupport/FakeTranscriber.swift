import Foundation
import ShellXAppCore

/// A `SpeechTranscribing` the test drives: `say(_:)` sends the words heard so far, `fail(_:)` ends
/// the stream with an error, `finalText` is what `finish()` returns (by default the last words said).
/// It records each start, finish and cancel, and can hold starts until the test releases them.
public final class FakeTranscriber: SpeechTranscribing, @unchecked Sendable {
    /// One `start` call.
    public struct Start: Equatable, Sendable {
        public var locale: Locale
        public var contextualStrings: [String]
    }

    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<String, any Error>.Continuation?
    private var lastSaid = ""
    private var finalAnswer: String?
    private var storedStartError: (any Error)?
    private var startList: [Start] = []
    private var finishCount = 0
    private var cancelCount = 0
    private var holding = false
    private var heldStarts: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Every start, in order.
    public var starts: [Start] { lock.withLock { startList } }
    public var finishCalls: Int { lock.withLock { finishCount } }
    public var cancelCalls: Int { lock.withLock { cancelCount } }
    /// A stream is open: started, and not finished, cancelled or failed.
    public var isRunning: Bool { lock.withLock { continuation != nil } }
    /// Starts held by `holdStarts()`.
    public var startsWaiting: Int { lock.withLock { heldStarts.count } }

    /// What `finish()` returns; nil returns the last words said.
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

    /// Sends `text` as everything heard so far.
    public func say(_ text: String) {
        let open = lock.withLock { () -> AsyncThrowingStream<String, any Error>.Continuation? in
            guard let current = self.continuation else { return nil }
            lastSaid = text
            return current
        }
        open?.yield(text)
    }

    /// Ends the stream with `error`, as a recognizer that fails does.
    public func fail(_ error: any Error) {
        let continuation = lock.withLock { () -> AsyncThrowingStream<String, any Error>.Continuation? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish(throwing: error)
    }

    // MARK: - SpeechTranscribing

    public func start(locale: Locale, contextualStrings: [String]) async throws -> AsyncThrowingStream<String, any Error> {
        let hold = lock.withLock { () -> Bool in
            startList.append(Start(locale: locale, contextualStrings: contextualStrings))
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
        let previous = lock.withLock { () -> AsyncThrowingStream<String, any Error>.Continuation? in
            defer {
                self.continuation = continuation
                lastSaid = ""
            }
            return self.continuation
        }
        previous?.finish()
        return stream
    }

    public func finish() async -> String {
        let (continuation, text) = lock.withLock { () -> (AsyncThrowingStream<String, any Error>.Continuation?, String) in
            finishCount += 1
            defer { self.continuation = nil }
            return (self.continuation, finalAnswer ?? lastSaid)
        }
        continuation?.finish()
        return text
    }

    public func cancel() async {
        let continuation = lock.withLock { () -> AsyncThrowingStream<String, any Error>.Continuation? in
            cancelCount += 1
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish()
    }
}
