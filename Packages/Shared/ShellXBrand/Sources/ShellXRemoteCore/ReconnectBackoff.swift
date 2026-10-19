import Foundation

public struct ReconnectBackoff: Sendable {
    /// `min(30, 2^attempt) * jitter` seconds; attempt 0 is 1 s.
    public static func delay(attempt: Int, jitter: Double = 1) -> TimeInterval {
        let exponent = min(max(attempt, 0), 10)
        return min(30, pow(2, Double(exponent))) * jitter
    }
}

public enum TicketSchedule {
    /// Refresh a relay ticket at half its remaining life, never sooner than 1 s.
    public static func nextRefresh(expiresAt: Date, now: Date) -> TimeInterval {
        max(1, expiresAt.timeIntervalSince(now) / 2)
    }
}
