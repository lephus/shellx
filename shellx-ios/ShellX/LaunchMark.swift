import ShellXAppCore

/// Measures `launchToHome` (spec section 7.4: opening the app shows the conversation in under 1 s):
/// from when the app built its object graph to when the home first shows its stored conversation.
/// One sample per launch, and none for a launch that had to sign in or pair first.
@MainActor
final class LaunchMark {
    private let latency: LatencyLog
    private let start = ContinuousClock.now
    private var done = false

    init(latency: LatencyLog) {
        self.latency = latency
    }

    func homeShown() {
        guard !done else { return }
        done = true
        latency.record(.launchToHome, ContinuousClock.now - start)
    }

    /// The launch did not go straight to the home (sign-in, or no Mac paired yet): no sample.
    func skip() {
        done = true
    }
}
