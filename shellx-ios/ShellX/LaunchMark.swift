import ShellXAppCore

/// Measures, from when the app built its object graph:
/// - `launchToHome` (spec section 7.4: opening the app shows the home in under 1 s): to when the home, the
///   workspace list, first shows, whether or not a Mac has listed its workspaces yet;
/// - `launchToWorkspaceList` (mobile workspaces spec section 2.2, criterion 1: the list shows in full in
///   under 1.5 s): to when the default Mac's workspace list first arrives.
///
/// One sample of each per launch, and none for a launch that had to sign in or pair first.
@MainActor
final class LaunchMark {
    private let latency: LatencyLog
    private let start = ContinuousClock.now
    private var homeDone = false
    private var listDone = false

    init(latency: LatencyLog) {
        self.latency = latency
    }

    func homeShown() {
        guard !homeDone else { return }
        homeDone = true
        latency.record(.launchToHome, ContinuousClock.now - start)
    }

    /// The default Mac's workspace list arrived.
    func workspacesListed() {
        guard !listDone else { return }
        listDone = true
        latency.record(.launchToWorkspaceList, ContinuousClock.now - start)
    }

    /// The launch did not go straight to the home (sign-in, or no Mac paired yet): no sample.
    func skip() {
        homeDone = true
        listDone = true
    }
}
