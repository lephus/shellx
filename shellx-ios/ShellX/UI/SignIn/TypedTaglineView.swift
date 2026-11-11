import SwiftUI

/// The line under the sign-in title: three taglines, typed one after another like at a terminal
/// (`TypewriterSchedule`), with a block cursor after the last letter. The cursor stays on while letters come and go
/// and blinks while the line rests.
///
/// The view is always as high as its tallest tagline needs, and at least two rows, so nothing under it moves. A
/// line is laid out whole from its first letter and the cursor is drawn from that same layout (`TypedLineView`),
/// so a word never jumps to the next row while it is typed and the cursor is always after the last typed letter.
/// VoiceOver reads the whole line being typed, not its letters.
///
/// Still (Reduce Motion, tests, screenshots): the first tagline, at once, with no cursor.
struct TypedTaglineView: View {
    /// Typing starts when the logo has settled.
    nonisolated static let startDelay: TimeInterval = SignInIntro.chevronSettle

    let motion: SignInIntroMotion
    /// When the intro began; typing starts `startDelay` later.
    let start: Date
    private let lines: [String]

    init(motion: SignInIntroMotion, start: Date = Date(), lines: [String] = TypedTaglineView.lines()) {
        self.motion = motion
        self.start = start
        self.lines = lines
    }

    /// The three taglines, in the app's language.
    nonisolated static func lines() -> [String] {
        [String(localized: "signin.tagline.1"), String(localized: "signin.tagline.2"), String(localized: "signin.tagline.3")]
    }

    var body: some View {
        Group {
            switch motion {
            case .animated:
                let schedule = TypewriterSchedule(lines: lines)
                let typingStart = start.addingTimeInterval(Self.startDelay)
                TimelineView(SignInIntroTimeline(start: typingStart, ticks: TypewriterTicks(schedule: schedule))) { context in
                    let time = context.date.timeIntervalSince(typingStart)
                    line(schedule.frame(at: time), cursorIsOn: schedule.cursorIsOn(at: time))
                }
            case .still:
                line(TypewriterSchedule.Frame(line: 0, text: lines.first ?? "", phase: .holding, nextChange: .infinity), cursorIsOn: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("signin.tagline")
    }

    /// The line of `frame` with its typed letters and, after them, the cursor while it is on.
    func line(_ frame: TypewriterSchedule.Frame, cursorIsOn: Bool) -> some View {
        let line = lines.indices.contains(frame.line) ? lines[frame.line] : ""
        return TypedLine(lines: lines, line: line, typed: frame.text, cursorIsOn: cursorIsOn)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: line))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// When the typed line is drawn again: at each letter typed or erased, each change of phase, and each turn of the
/// cursor's blink while the line rests.
struct TypewriterTicks: SignInIntroTicks {
    let schedule: TypewriterSchedule

    func next(after time: TimeInterval) -> TimeInterval? {
        let next = schedule.nextTick(after: time)
        return next.isFinite ? next : nil
    }
}
