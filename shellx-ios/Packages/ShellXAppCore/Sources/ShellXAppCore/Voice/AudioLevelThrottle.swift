import Foundation

/// How often the level bar is updated: about `rate` times a second of audio, counted in frames, so
/// the pace holds whatever buffer size the system hands over. Buffers longer than `1 / rate` seconds
/// (a device's tap often delivers about 100 ms) are each reported.
public struct AudioLevelThrottle: Sendable {
    public let rate: Double
    private var pending: Double = 0

    public init(rate: Double = 20) {
        self.rate = rate
    }

    /// Adds a buffer of `frames` at `sampleRate`; true when the bar is due an update.
    public mutating func take(frames: Int, sampleRate: Double) -> Bool {
        guard frames > 0, sampleRate > 0, rate > 0 else { return false }
        let every = sampleRate / rate
        pending += Double(frames)
        guard pending >= every else { return false }
        // Keep the remainder, so the pace stays even; never owe more than one update.
        pending = min(pending - every, every)
        return true
    }
}
