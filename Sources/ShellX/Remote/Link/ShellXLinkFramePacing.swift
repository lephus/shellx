import Foundation

/// When a Link view captures its next delta: the pull-based hand-off between the pump asking for a frame and cmux's
/// frame pacer (90 ms floor, an input's echo never held).
struct ShellXLinkFramePacing {
    enum Step: Equatable {
        case capture
        case hold(until: ContinuousClock.Instant)
    }

    private var pacer = MobileTerminalFramePacer()
    private var heldUntil: ContinuousClock.Instant?

    init() {}

    /// A change is waiting and the pump wants a frame.
    mutating func changeArrived(now: ContinuousClock.Instant, inputSequence: UInt64?) -> Step {
        switch pacer.updateArrived(now: now, acceptedInputSequence: inputSequence) {
        case .emit:
            heldUntil = nil
            return .capture
        case .coalesce:
            return .hold(until: heldUntil ?? now)
        case .coalesceAndSchedule(let deadline):
            heldUntil = deadline
            return .hold(until: deadline)
        }
    }

    /// The held time passed: capture now (true), or nothing was held back (false).
    mutating func holdEnded(now: ContinuousClock.Instant) -> Bool {
        heldUntil = nil
        return pacer.flushFired(now: now)
    }

    /// A snapshot (outside the pacer) went out now.
    mutating func noteSnapshot(now: ContinuousClock.Instant, inputSequence: UInt64?) {
        heldUntil = nil
        pacer.noteUnpacedEmit(now: now, acceptedInputSequence: inputSequence)
    }
}
