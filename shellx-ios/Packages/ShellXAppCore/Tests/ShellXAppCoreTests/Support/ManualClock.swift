import Foundation

/// A clock the test moves by hand: `now` changes only through `advance(by:)`, so a measured
/// duration is exactly what the test advanced. `sleep(until:)` returns once the clock reaches the
/// deadline (or throws when its task is cancelled).
final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [UUID: (deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = [:]

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    /// Moves the clock forward and wakes every sleeper whose deadline passed.
    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            current = current.advanced(by: duration)
            let ids = sleepers.filter { $0.value.deadline <= current }.map(\.key)
            return ids.compactMap { sleepers.removeValue(forKey: $0)?.continuation }
        }
        for continuation in due { continuation.resume() }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if deadline <= current {
                    lock.unlock()
                    continuation.resume()
                } else {
                    sleepers[id] = (deadline, continuation)
                    lock.unlock()
                }
            }
        } onCancel: {
            let sleeper = lock.withLock { sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }
}
