import SwiftUI

/// Whether the sign-in intro moves. Still: the logo is drawn at rest, the first tagline shows at once, the guide is
/// there, and nothing slides, types, glows or blinks.
enum SignInIntroMotion: Equatable, Sendable {
    case animated
    case still

    /// Still with Reduce Motion on, and in a test or screenshot run (so every render there is the same).
    static func decide(reduceMotion: Bool, underTest: Bool) -> SignInIntroMotion {
        reduceMotion || underTest ? .still : .animated
    }

    /// Whether `environment` is that of a test run (XCTest sets `XCTest…` variables in the app it hosts) or of a
    /// screenshot run (`dev.sh screenshots` sets `SHELLX_SNAPSHOT_DIR`).
    static func isUnderTest(environment: [String: String]) -> Bool {
        if let directory = environment["SHELLX_SNAPSHOT_DIR"], !directory.isEmpty { return true }
        return environment.keys.contains { $0.hasPrefix("XCTest") }
    }

    /// Whether this process is a test or screenshot run. Like the app's other environment switches, only a Debug
    /// build reads it: tests and screenshots never run a Release build.
    static let underTest: Bool = {
        #if DEBUG
        return isUnderTest(environment: ProcessInfo.processInfo.environment)
        #else
        return false
        #endif
    }()
}

/// The timing of the sign-in intro, in seconds after the screen appears: the two chevrons of the logo slide in
/// and settle, the underscore appears and then blinks, and the glow behind the logo starts to breathe. The typed
/// tagline and the guide start when the chevrons have settled (`chevronSettle`).
enum SignInIntro {
    /// When the chevrons are furthest past their place.
    static let chevronPeak: TimeInterval = 0.45
    /// When the chevrons are back in their place for good.
    static let chevronSettle: TimeInterval = 0.6
    /// When the underscore has fully appeared.
    static let underscoreShown: TimeInterval = 0.75
    /// When the intro is over: the underscore starts to blink and the glow to breathe.
    static let end: TimeInterval = 0.9
    /// How far past their place the chevrons go, as a part of the way they came.
    static let overshoot = 0.04
    /// How far out a chevron starts, as a part of the logo's side. A chevron reaches 249/512 of the side from its
    /// edge (222 + half the 54-unit stroke), so at 0.55 it is wholly outside the square, which clips it.
    static let chevronStart = 0.55
    /// The time between two frames while something slides.
    static let frame: TimeInterval = 1.0 / 60
    /// The glow's opacity at the ends of a breath, and how long a breath takes.
    static let glowLow = 0.25
    static let glowHigh = 0.45
    static let glowBreath: TimeInterval = 4
    /// A moment that comes this much early still counts as on time: a `Date` keeps about a tenth of a microsecond,
    /// so the time since the start can fall just short of the tick it was scheduled for.
    static let tolerance: TimeInterval = 1e-6

    /// How far the chevrons have come at `time`: 0 outside, 1 in place. A cubic ease-out to `1 + overshoot` at
    /// `chevronPeak`, then a smooth return to 1 at `chevronSettle`.
    static func slideProgress(at time: TimeInterval) -> Double {
        if time <= 0 { return 0 }
        if time >= chevronSettle { return 1 }
        if time <= chevronPeak {
            let left = 1 - time / chevronPeak
            return (1 + overshoot) * (1 - left * left * left)
        }
        let back = (time - chevronPeak) / (chevronSettle - chevronPeak)
        return 1 + overshoot * (1 - back * back * (3 - 2 * back))
    }

    /// Where the left chevron is at `time`, as a part of the logo's side: `-chevronStart` (outside, to the left) at
    /// the start, 0 in place, a little positive at the peak.
    static func chevronOffset(at time: TimeInterval) -> Double {
        -chevronStart * (1 - slideProgress(at: time))
    }

    /// The right chevron mirrors the left one.
    static func rightChevronOffset(at time: TimeInterval) -> Double {
        -chevronOffset(at: time)
    }

    /// The underscore's opacity at `time`: nothing until the chevrons settle, a fade in until `underscoreShown`, on
    /// until `end`, then a terminal cursor's blink.
    static func underscoreOpacity(at time: TimeInterval) -> Double {
        let now = time + tolerance
        if now < chevronSettle { return 0 }
        if now < underscoreShown { return min(1, max(0, (time - chevronSettle) / (underscoreShown - chevronSettle))) }
        return CursorBlink.isOn(elapsed: time - end) ? 1 : 0
    }

    /// The opacity of the glow behind the logo at `time`: nothing until the chevrons settle, a fade in to `glowLow`
    /// at `end`, then a breath to `glowHigh` and back every `glowBreath` seconds.
    static func glowOpacity(at time: TimeInterval) -> Double {
        if time <= chevronSettle { return 0 }
        if time < end { return glowLow * (time - chevronSettle) / (end - chevronSettle) }
        let phase = (time - end).truncatingRemainder(dividingBy: glowBreath) / glowBreath
        return glowLow + (glowHigh - glowLow) * (1 - cos(2 * .pi * phase)) / 2
    }
}

/// A terminal cursor's blink: on for `half`, off for `half`.
enum CursorBlink {
    static let half: TimeInterval = 0.53

    /// Whether the cursor shows `elapsed` seconds after its blink started. Before the start it is simply on.
    static func isOn(elapsed: TimeInterval) -> Bool {
        let now = elapsed + SignInIntro.tolerance
        guard now > 0 else { return true }
        return now.truncatingRemainder(dividingBy: 2 * half) < half
    }

    /// The first moment after `elapsed` at which the cursor turns on or off.
    static func nextToggle(after elapsed: TimeInterval) -> TimeInterval {
        let now = elapsed + SignInIntro.tolerance
        guard now > 0 else { return half }
        return ((now / half).rounded(.down) + 1) * half
    }
}

/// What a typewriter shows over time: each line is typed a letter at a time, held, erased a letter at a time,
/// then a pause, and the next line; after the last line, the first again. Times are seconds after typing starts.
struct TypewriterSchedule: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case typing
        case holding
        case erasing
        case pausing
    }

    /// What shows at one moment.
    struct Frame: Equatable, Sendable {
        /// The index of the line being typed, held or erased.
        let line: Int
        /// The letters of it that show.
        let text: String
        let phase: Phase
        /// When the text or the phase next changes.
        let nextChange: TimeInterval
    }

    /// The lines, as the letters a reader sees (a letter with its accents is one).
    let lines: [[Character]]
    /// Seconds per letter typed.
    let typeInterval: TimeInterval
    /// Seconds a whole line stays.
    let hold: TimeInterval
    /// Seconds per letter erased.
    let eraseInterval: TimeInterval
    /// Seconds with nothing before the next line.
    let pause: TimeInterval

    init(
        lines: [String], typeInterval: TimeInterval = 0.028, hold: TimeInterval = 2.4, eraseInterval: TimeInterval = 0.012,
        pause: TimeInterval = 0.3
    ) {
        self.lines = lines.map(Array.init)
        self.typeInterval = typeInterval
        self.hold = hold
        self.eraseInterval = eraseInterval
        self.pause = pause
    }

    /// How long line `index` takes from its first letter to the end of the pause after it.
    func lineDuration(_ index: Int) -> TimeInterval {
        let letters = Double(lines[index].count)
        return letters * typeInterval + hold + letters * eraseInterval + pause
    }

    /// How long all the lines take; then they start again.
    var cycle: TimeInterval {
        lines.indices.reduce(0) { $0 + lineDuration($1) }
    }

    /// What shows at `time`. Before typing starts: nothing, and the next change is the start.
    func frame(at time: TimeInterval) -> Frame {
        let cycle = cycle
        guard cycle > 0 else { return Frame(line: 0, text: "", phase: .pausing, nextChange: .infinity) }
        let now = time + SignInIntro.tolerance
        guard now >= 0 else { return Frame(line: 0, text: "", phase: .pausing, nextChange: 0) }

        let round = (now / cycle).rounded(.down)
        let base = round * cycle
        var lineStart = 0.0
        var index = 0
        while index < lines.count - 1, now - base >= lineStart + lineDuration(index) {
            lineStart += lineDuration(index)
            index += 1
        }
        let letters = lines[index]
        let local = now - base - lineStart
        let typed = Double(letters.count) * typeInterval
        let erased = typed + hold + Double(letters.count) * eraseInterval
        // The end of the last line is the start of the next round, to the last bit: no sum of parts in between.
        let lineEnd = index == lines.count - 1 ? (round + 1) * cycle : base + lineStart + lineDuration(index)

        let frame: Frame
        if local < typed {
            let step = (local / typeInterval).rounded(.down)
            let shown = min(letters.count, Int(step) + 1)
            frame = Frame(
                line: index, text: String(letters.prefix(shown)), phase: .typing,
                nextChange: base + lineStart + (step + 1) * typeInterval)
        } else if local < typed + hold {
            frame = Frame(line: index, text: String(letters), phase: .holding, nextChange: base + lineStart + typed + hold)
        } else if local < erased {
            let step = ((local - typed - hold) / eraseInterval).rounded(.down)
            let shown = max(0, letters.count - 1 - Int(step))
            frame = Frame(
                line: index, text: String(letters.prefix(shown)), phase: .erasing,
                nextChange: base + lineStart + typed + hold + (step + 1) * eraseInterval)
        } else {
            frame = Frame(line: index, text: "", phase: .pausing, nextChange: lineEnd)
        }
        // Far into a long stay a step is smaller than the clock can tell apart: never answer "now".
        return frame.nextChange > time ? frame : Frame(line: frame.line, text: frame.text, phase: frame.phase, nextChange: time.nextUp)
    }

    /// Whether the block cursor after the typed letters shows at `time`: it stays on while letters come and go (as
    /// a terminal's does while one types) and blinks while the line rests.
    func cursorIsOn(at time: TimeInterval) -> Bool {
        guard let rest = restStart(at: time) else { return true }
        return CursorBlink.isOn(elapsed: time - rest)
    }

    /// The first moment after `time` at which the text, the phase or the cursor changes.
    func nextTick(after time: TimeInterval) -> TimeInterval {
        let change = frame(at: time).nextChange
        guard let rest = restStart(at: time) else { return change }
        return min(change, rest + CursorBlink.nextToggle(after: time - rest))
    }

    /// When the rest the line is in at `time` began (it is held, or the pause after it runs); nil while letters
    /// come and go.
    private func restStart(at time: TimeInterval) -> TimeInterval? {
        let frame = frame(at: time)
        switch frame.phase {
        case .typing, .erasing: return nil
        case .holding: return frame.nextChange - hold
        case .pausing: return frame.nextChange - pause
        }
    }
}

/// How the sign-in screen lays itself out in `size`, the room inside the safe area.
struct SignInLayout: Equatable, Sendable {
    /// The logo's side: 96 points, 72 in a window under 600 points high or wider than it is high.
    let logoSize: CGFloat
    /// Whether the subtitle shows under the taglines: only in 700 points of height or more.
    let showsSubtitle: Bool
    /// Whether the three steps show: not under 400 points of height.
    let showsGuide: Bool
    /// Landscape: the logo, the title and the taglines on the left, the steps and the buttons on the right.
    let sideBySide: Bool

    init(size: CGSize) {
        sideBySide = size.width > size.height
        logoSize = size.height < 600 || size.width > size.height ? 72 : 96
        showsSubtitle = size.height >= 700
        showsGuide = size.height >= 400
    }
}

/// The moments a part of the intro is drawn again, in seconds after the intro's start.
protocol SignInIntroTicks: Sendable {
    /// The first moment after `time` at which the part looks different; nil once it has come to rest for good.
    func next(after time: TimeInterval) -> TimeInterval?
}

/// A `TimelineView` schedule made of a part's ticks: the view is drawn at the moment it appears, then at each tick
/// after it, and never again once the part has come to rest. It holds no timer of its own: a view that has left
/// the screen is not asked for more.
struct SignInIntroTimeline<Ticks: SignInIntroTicks>: TimelineSchedule {
    /// When the intro began.
    let start: Date
    let ticks: Ticks

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(start: start, ticks: ticks, time: startDate.timeIntervalSince(start))
    }

    struct Entries: Sequence, IteratorProtocol {
        /// The shortest time between two entries, whatever the ticks say.
        static var shortest: TimeInterval { 0.001 }

        let start: Date
        let ticks: Ticks
        /// The next entry, in seconds after `start`; nil after the last one.
        var time: TimeInterval?

        mutating func next() -> Date? {
            guard let now = time else { return nil }
            time = ticks.next(after: now).flatMap { $0.isFinite ? Swift.max($0, now + Self.shortest) : nil }
            return start.addingTimeInterval(now)
        }
    }
}
