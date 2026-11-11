import SwiftUI

/// The three steps under the sign-in taglines: a number in a tinted circle and one sentence each.
///
/// Animated: the rows appear one after another once the logo has settled, 80 ms apart, each fading in and sliding
/// up 8 points over 250 ms; then they stay. They hold their room from the start, so nothing under them moves, and
/// VoiceOver reads them whether they have appeared or not. Still (Reduce Motion, tests, screenshots): all three
/// are there at once.
struct SignInGuideView: View {
    nonisolated static let rows = 3
    /// Seconds between two rows.
    nonisolated static let gap: TimeInterval = 0.08
    /// Seconds a row takes to appear.
    nonisolated static let fade: TimeInterval = 0.25
    /// Points a row comes up from.
    nonisolated static let slide: CGFloat = 8

    let motion: SignInIntroMotion
    /// When the intro began.
    let start: Date

    @ScaledMetric(relativeTo: .subheadline) private var circle: CGFloat = 28

    init(motion: SignInIntroMotion, start: Date = Date()) {
        self.motion = motion
        self.start = start
    }

    /// When row `row` (from 0) starts to appear, in seconds after the intro's start.
    nonisolated static func revealTime(row: Int) -> TimeInterval {
        SignInIntro.chevronSettle + gap * Double(row)
    }

    /// How far row `row` has come at `time`: 0 unseen and `slide` points low, 1 in place. It eases out.
    nonisolated static func progress(row: Int, at time: TimeInterval) -> Double {
        let part = min(1, max(0, (time - revealTime(row: row)) / fade))
        return 1 - (1 - part) * (1 - part)
    }

    var body: some View {
        switch motion {
        case .animated:
            TimelineView(SignInIntroTimeline(start: start, ticks: SignInGuideTicks())) { context in
                let time = context.date.timeIntervalSince(start)
                steps(progress: (0..<Self.rows).map { Self.progress(row: $0, at: time) })
            }
        case .still:
            steps(progress: Array(repeating: 1, count: Self.rows))
        }
    }

    /// The rows, each as far in as `progress` says (0 unseen, 1 in place).
    private func steps(progress: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<Self.rows, id: \.self) { row in
                let shown = progress[row]
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: "\(row + 1)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color("StatusDone"))
                        .frame(width: circle, height: circle)
                        .background(Color("StatusDone").opacity(0.15), in: Circle())
                    Text(Self.step(row))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(shown)
                .offset(y: (1 - shown) * Self.slide)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("signin.guide")
    }

    private static func step(_ row: Int) -> LocalizedStringResource {
        switch row {
        case 0: LocalizedStringResource("signin.guide.1")
        case 1: LocalizedStringResource("signin.guide.2")
        default: LocalizedStringResource("signin.guide.3")
        }
    }
}

/// When the guide is drawn again: every frame from the first row's start until the last row is in place, then
/// never.
struct SignInGuideTicks: SignInIntroTicks {
    func next(after time: TimeInterval) -> TimeInterval? {
        let first = SignInGuideView.revealTime(row: 0)
        let last = SignInGuideView.revealTime(row: SignInGuideView.rows - 1) + SignInGuideView.fade
        if time + SignInIntro.tolerance < first { return first }
        if time + SignInIntro.tolerance < last { return min(time + SignInIntro.frame, last) }
        return nil
    }
}
