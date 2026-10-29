import Foundation

/// The microphone holds one dictation at a time; this decides which. Every transcriber that shares
/// the microphone shares one slot.
///
/// - `begin` marks a start: the newest start is the only one that may take the microphone. The
///   outermost transcriber begins a press at its entry, before any await; beginning the same run
///   again later changes nothing.
/// - `claim` is asked right before the audio starts. A start that a newer one overtook, or whose run
///   was cancelled while it started (or before), is refused: it cleans up after itself and leaves
///   the active run alone. A granted claim hands back the run it replaced, which the caller tears down.
/// - `cancel`, `takeForFinish` and `ended` act on the run they name only.
///
/// Thread-safe: every call is short and never waits while holding the lock.
public final class SpeechRunSlot: @unchecked Sendable {
    /// How a transcriber finishes or tears down the run it claimed with.
    public struct Handlers: Sendable {
        public let finish: @Sendable () async -> String
        public let teardown: @Sendable () async -> Void

        public init(finish: @escaping @Sendable () async -> String, teardown: @escaping @Sendable () async -> Void) {
            self.finish = finish
            self.teardown = teardown
        }
    }

    public enum Claim: Sendable {
        /// The run holds the microphone now; tear down `replaced` (the run it took over from), if any.
        case granted(replaced: Handlers?)
        /// Overtaken or cancelled: never start the audio; clean up and end the run's stream.
        case refused
    }

    /// Cancels remembered for runs that are not active (bounded, oldest dropped).
    private static let cancelMemory = 32
    /// Runs remembered as begun, so beginning one again changes nothing (bounded, oldest dropped).
    private static let beginMemory = 32

    private let lock = NSLock()
    private var newest: SpeechRunID?
    private var begun: [SpeechRunID] = []
    private var current: (run: SpeechRunID, handlers: Handlers)?
    private var cancelled: [SpeechRunID] = []

    public init() {}

    /// The run that holds the microphone.
    public var active: SpeechRunID? { lock.withLock { current?.run } }

    public func isActive(_ run: SpeechRunID) -> Bool {
        lock.withLock { current?.run == run }
    }

    /// A start of `run` began; it is the newest start now, unless `run` began before. Beginning a run
    /// again (an inner transcriber after the router, a fallback retry) never makes an older run the
    /// newest again.
    public func begin(_ run: SpeechRunID) {
        lock.withLock {
            guard !begun.contains(run) else { return }
            begun.append(run)
            if begun.count > Self.beginMemory { begun.removeFirst(begun.count - Self.beginMemory) }
            newest = run
        }
    }

    /// `run` is ready to take the microphone.
    public func claim(_ run: SpeechRunID, _ handlers: Handlers) -> Claim {
        lock.withLock {
            guard newest == run, !cancelled.contains(run) else { return .refused }
            let replaced = current?.handlers
            current = (run, handlers)
            return .granted(replaced: replaced)
        }
    }

    /// Cancels `run`: its handlers when it holds the microphone (the caller tears it down);
    /// otherwise nil, and a start of `run` still under way (or not yet begun) will be refused.
    public func cancel(_ run: SpeechRunID) -> Handlers? {
        lock.withLock {
            if let current, current.run == run {
                self.current = nil
                return current.handlers
            }
            if !cancelled.contains(run) {
                cancelled.append(run)
                if cancelled.count > Self.cancelMemory { cancelled.removeFirst(cancelled.count - Self.cancelMemory) }
            }
            return nil
        }
    }

    /// `run` is released to finish: its handlers when it holds the microphone (it no longer does).
    public func takeForFinish(_ run: SpeechRunID) -> Handlers? {
        lock.withLock {
            guard let current, current.run == run else { return nil }
            self.current = nil
            return current.handlers
        }
    }

    /// `run` ended by itself (an error, a time limit). True when it held the microphone until now:
    /// the caller gives the audio back.
    public func ended(_ run: SpeechRunID) -> Bool {
        lock.withLock {
            guard current?.run == run else { return false }
            current = nil
            return true
        }
    }
}
