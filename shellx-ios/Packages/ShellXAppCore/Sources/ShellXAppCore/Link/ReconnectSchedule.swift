import Foundation

/// How long to wait before the next attempt to reach a Mac.
public struct ReconnectSchedule: Sendable {
    /// The wait after 1, 2, 3, ... failures in a row; the last one repeats.
    public var steps: [Duration]
    /// The largest share by which a wait may be longer or shorter (0.2 = 20 %).
    public var jitterFraction: Double

    public init(steps: [Duration], jitterFraction: Double) {
        precondition(!steps.isEmpty, "a schedule needs at least one step")
        self.steps = steps
        self.jitterFraction = jitterFraction
    }

    /// 0.5, 1, 2, 4, 8, 15, then 30 s for good, each up to 20 % longer or shorter.
    public static let standard = ReconnectSchedule(
        steps: [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)],
        jitterFraction: 0.2)

    /// The wait after `afterFailures` failures in a row (a session that ended counts as one), zero
    /// when there was none. `jitter` in -1...1 (clamped) moves the wait by up to `jitterFraction`,
    /// so phones that lost the same relay do not all come back at the same instant.
    public func delay(afterFailures failures: Int, jitter: Double) -> Duration {
        guard failures > 0 else { return .zero }
        let base = steps[min(failures, steps.count) - 1]
        let clamped = min(max(jitter, -1), 1)
        return base * (1 + clamped * jitterFraction)
    }
}
