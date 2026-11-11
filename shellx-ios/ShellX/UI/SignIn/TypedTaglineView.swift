import SwiftUI
import UIKit

/// The line under the sign-in title: three taglines, typed one after another like at a terminal
/// (`TypewriterSchedule`), with a block cursor after the last letter. The cursor stays on while letters come and go
/// and blinks while the line rests.
///
/// The view is always as high as its tallest tagline needs, and at least two lines, so nothing under it moves. A
/// line is laid out whole from its first letter: the letters not typed yet are there, unseen, and so is the room
/// of the cursor at the line's end, where it comes to rest. On its way there the cursor takes no room, so a word
/// never jumps to the next row while it is typed. VoiceOver reads the whole line being typed, not its letters.
///
/// Still (Reduce Motion, tests, screenshots): the first tagline, at once, with no cursor.
struct TypedTaglineView: View {
    /// Typing starts when the logo has settled.
    nonisolated static let startDelay: TimeInterval = SignInIntro.chevronSettle
    /// The cursor: a block, as wide as a terminal's.
    nonisolated static let cursor = "▍"
    /// The taglines' text style.
    private static let textStyle = (font: Font.title3, uiFont: UIFont.TextStyle.title3)

    let motion: SignInIntroMotion
    /// When the intro began; typing starts `startDelay` later.
    let start: Date
    private let lines: [String]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        ZStack(alignment: .topLeading) {
            // The room the tallest line needs with the cursor at its end; never seen.
            ForEach(lines.indices, id: \.self) { index in
                Text(verbatim: lines[index] + Self.cursor).hidden()
            }
            switch motion {
            case .animated:
                let schedule = TypewriterSchedule(lines: lines)
                let typingStart = start.addingTimeInterval(Self.startDelay)
                let advance = Self.cursorAdvance(dynamicTypeSize)
                TimelineView(SignInIntroTimeline(start: typingStart, ticks: TypewriterTicks(schedule: schedule))) { context in
                    let time = context.date.timeIntervalSince(typingStart)
                    typed(schedule.frame(at: time), cursorIsOn: schedule.cursorIsOn(at: time), cursorAdvance: advance)
                }
            case .still:
                Text(verbatim: lines.first ?? "")
            }
        }
        .font(Self.textStyle.font)
        .foregroundStyle(.primary)
        .lineLimit(2...)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("signin.tagline")
    }

    /// The line of `frame` with its typed letters and, after them, the cursor. The letters and the cursor are two
    /// texts over each other, each with the rest of the line unseen in it and each given the same room, so both
    /// are laid out as the whole line with the cursor at its end. (The cursor is not an overlay of the letters: it
    /// would get exactly the letters' width, and wrap as soon as it came out a hair wider.)
    func typed(_ frame: TypewriterSchedule.Frame, cursorIsOn: Bool, cursorAdvance: CGFloat) -> some View {
        let line = lines.indices.contains(frame.line) ? lines[frame.line] : ""
        let parts = Self.parts(of: line, typed: frame.text.count)
        return ZStack(alignment: .topLeading) {
            Text(Self.letters(parts))
            Text(Self.cursorLine(parts, isOn: cursorIsOn, advance: cursorAdvance))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line))
    }

    /// `line` cut after its first `typed` letters.
    nonisolated static func parts(of line: String, typed: Int) -> (typed: String, rest: String) {
        let cut = line.index(line.startIndex, offsetBy: max(0, typed), limitedBy: line.endIndex) ?? line.endIndex
        return (String(line[..<cut]), String(line[cut...]))
    }

    /// The typed letters, then, unseen, the rest of the line and the room of the cursor at its end.
    static func letters(_ parts: (typed: String, rest: String)) -> AttributedString {
        AttributedString(parts.typed) + unseen(parts.rest + cursor)
    }

    /// The cursor after the typed letters, in the theme's green while it is on; the letters before and after it
    /// unseen. After the last letter it stands in the room kept for it. Before that it is drawn where the next
    /// letter will be and takes no room: what follows it is pulled back by `advance`, its own width, so the line
    /// breaks exactly as `letters` does. (It cannot do without that room at the end: a text is not drawn outside
    /// its own lines.)
    static func cursorLine(_ parts: (typed: String, rest: String), isOn: Bool, advance: CGFloat) -> AttributedString {
        var block = AttributedString(cursor)
        block.swiftUI.foregroundColor = isOn ? Color("StatusDone") : .clear
        guard !parts.rest.isEmpty else { return unseen(parts.typed) + block }
        block.swiftUI.kern = -advance
        return unseen(parts.typed) + block + unseen(parts.rest + cursor)
    }

    /// How far the cursor moves the letter after it, in the taglines' font at `size`: the width to take back so that
    /// it takes none. The font has no block of its own, so this is the width of the one the system puts in its place.
    static func cursorAdvance(_ size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let font = UIFont.preferredFont(forTextStyle: textStyle.uiFont, compatibleWith: traits)
        return (cursor as NSString).size(withAttributes: [.font: font]).width
    }

    private static func unseen(_ text: String) -> AttributedString {
        var unseen = AttributedString(text)
        unseen.swiftUI.foregroundColor = .clear
        return unseen
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
