import Foundation
import os

/// The latencies the app measures against its targets (spec section 7.4).
public enum LatencyMetric: String, CaseIterable, Sendable {
    /// Tap on a decision to the Mac's `reply_result`.
    case replyRoundTrip
    /// A request created on the Mac to its arrival on the phone.
    case pendingArrival
    /// A session's state change on the Mac to its arrival on the phone.
    case sessionChangeArrival
    /// App launch to the home screen with content.
    case launchToHome
    /// Start of speech to the first recognised word.
    case firstWord
}

public struct LatencySummary: Equatable, Sendable {
    public var count: Int
    public var p50: Duration
    public var p95: Duration

    public init(count: Int, p50: Duration, p95: Duration) {
        self.count = count
        self.p50 = p50
        self.p95 = p95
    }
}

/// Keeps the last `window` samples of each metric and logs each one. Safe from any thread.
///
/// A log line carries only the metric name and milliseconds, never content or identifiers.
public final class LatencyLog: Sendable {
    public static let window = 200

    private let samples = OSAllocatedUnfairLock(initialState: [LatencyMetric: [Duration]]())
    private let log = Logger(subsystem: "com.shellx.app", category: "latency")

    public init() {}

    /// Records one sample. A negative duration (the two clocks disagree) counts as zero.
    public func record(_ metric: LatencyMetric, _ duration: Duration) {
        let value = max(duration, .zero)
        samples.withLock { all in
            var list = all[metric, default: []]
            list.append(value)
            if list.count > Self.window { list.removeFirst(list.count - Self.window) }
            all[metric] = list
        }
        let milliseconds = Self.milliseconds(value)
        log.info("\(metric.rawValue, privacy: .public) \(milliseconds, privacy: .public) ms")
    }

    /// Count, median and 95th percentile (nearest rank) of the last `window` samples; nil when none.
    public func summary(_ metric: LatencyMetric) -> LatencySummary? {
        let sorted = samples.withLock { $0[metric] ?? [] }.sorted()
        guard !sorted.isEmpty else { return nil }
        return LatencySummary(
            count: sorted.count, p50: Self.percentile(0.50, of: sorted), p95: Self.percentile(0.95, of: sorted))
    }

    private static func percentile(_ fraction: Double, of sorted: [Duration]) -> Duration {
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    private static func milliseconds(_ duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
