import SwiftUI

/// The ShellX mark drawn in code, so its parts can move: the dark rounded square of the app icon, the mint ">"
/// (the computer's prompt) on the left, the lilac "<" (the phone) on the right, and the mint underscore.
///
/// Animated, once each time the screen appears (`SignInIntro`): the two chevrons slide in from the left and the
/// right edge and settle with a small overshoot, the underscore appears and then blinks like a terminal's cursor,
/// and a soft halo comes up behind the square: a ring of the brand's five soft colours that turns around the logo
/// once every six seconds and breathes. Still (Reduce Motion, tests, screenshots): the mark at rest, the same as
/// the `Logo` asset and the app icon, with no halo and no blink.
///
/// Everything is a function of the time since `start`, read from a `TimelineView`: nothing runs once the view
/// has left the screen.
struct SignInLogoView: View {
    /// The side of the square, in points.
    let size: CGFloat
    let motion: SignInIntroMotion
    /// When the intro began.
    let start: Date

    @Environment(\.colorScheme) private var colorScheme

    init(size: CGFloat, motion: SignInIntroMotion, start: Date = Date()) {
        self.size = size
        self.motion = motion
        self.start = start
    }

    var body: some View {
        ZStack {
            switch motion {
            case .animated:
                // The halo turns and breathes slowly: 30 frames a second are plenty, and a frame only changes its
                // rotation and its opacity.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    halo(at: context.date.timeIntervalSince(start))
                }
                TimelineView(SignInIntroTimeline(start: start, ticks: SignInLogoTicks())) { context in
                    let time = context.date.timeIntervalSince(start)
                    mark(chevron: SignInIntro.chevronOffset(at: time), underscore: SignInIntro.underscoreOpacity(at: time))
                }
            case let .at(time):
                halo(at: time)
                mark(chevron: SignInIntro.chevronOffset(at: time), underscore: SignInIntro.underscoreOpacity(at: time))
            case .still:
                mark(chevron: 0, underscore: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringResource("signin.logo")))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("signin.logo")
    }

    /// One 512th of the side: the mark is given in the 512 units of `design/shellx-logo.svg`.
    private var unit: CGFloat { size / SignInLogoMark.side }

    private var square: RoundedRectangle {
        RoundedRectangle(cornerRadius: SignInLogoMark.cornerRadius * unit, style: .circular)
    }

    /// The halo behind the square at `time`: the five colours around the logo's centre, turned as far as they have
    /// come, seen through the square's own shape, a little larger and blurred, at the opacity of its breath. So the
    /// halo is a soft ring that follows the square's outline, strong at its edge and gone some 0.23 of its side
    /// further out (`haloExtent`). The colours are one layer that only turns; the shape they are seen through stands
    /// still. The halo is drawn outside the logo's frame and takes no room.
    private func halo(at time: TimeInterval) -> some View {
        let spread = size * SignInLogoMark.haloSpread
        let field = size * SignInLogoMark.haloField
        return AngularGradient(colors: SignInLogoMark.haloColors, center: .center)
            .frame(width: field, height: field)
            .rotationEffect(.degrees(SignInIntro.haloAngle(at: time)))
            .mask {
                RoundedRectangle(cornerRadius: SignInLogoMark.cornerRadius * unit + spread, style: .circular)
                    .fill(Color.black)
                    .frame(width: size + 2 * spread, height: size + 2 * spread)
                    .blur(radius: size * SignInLogoMark.haloSoftness)
            }
            .opacity(SignInIntro.haloOpacity(at: time, dark: colorScheme == .dark))
            .allowsHitTesting(false)
    }

    /// The mark with the left chevron `chevron` sides from its place (the right one mirrors it) and the underscore
    /// at `underscore` opacity. The square clips the chevrons, so they come in from its edges.
    private func mark(chevron: Double, underscore: Double) -> some View {
        let line = StrokeStyle(lineWidth: SignInLogoMark.stroke * unit, lineCap: .round, lineJoin: .round)
        return ZStack {
            square.fill(LinearGradient(colors: SignInLogoMark.background, startPoint: .top, endPoint: .bottom))
            RadialGradient(
                colors: [SignInLogoMark.glow.opacity(0.22), SignInLogoMark.glow.opacity(0)],
                center: SignInLogoMark.innerGlowCenter, startRadius: 0, endRadius: SignInLogoMark.innerGlowRadius * size)
            SignInMarkBorder()
                .stroke(Color.white.opacity(0.09), lineWidth: SignInLogoMark.borderWidth * unit)
            SignInMarkLine(points: SignInLogoMark.prompt)
                .stroke(SignInLogoMark.promptGradient, style: line)
                .offset(x: chevron * size)
            SignInMarkLine(points: SignInLogoMark.phone)
                .stroke(SignInLogoMark.phoneGradient, style: line)
                .offset(x: -chevron * size)
            SignInMarkCursor()
                .fill(SignInLogoMark.cursorGradient)
                .opacity(underscore)
        }
        .frame(width: size, height: size)
        .clipShape(square)
    }
}

/// When the logo is drawn again: every frame until the intro is over, then each time the underscore turns on or
/// off.
struct SignInLogoTicks: SignInIntroTicks {
    func next(after time: TimeInterval) -> TimeInterval? {
        if time < -SignInIntro.tolerance { return 0 }
        if time + SignInIntro.tolerance < SignInIntro.end { return min(time + SignInIntro.frame, SignInIntro.end) }
        return SignInIntro.end + CursorBlink.nextToggle(after: time - SignInIntro.end)
    }
}

/// The mark's geometry and colours, in the 512 units of `design/shellx-logo.svg` (the app icon and the `Logo`
/// asset are that drawing).
enum SignInLogoMark {
    static let side: CGFloat = 512
    static let cornerRadius: CGFloat = 114
    /// The chevrons' line width; round caps and joins.
    static let stroke: CGFloat = 54
    /// ">" on the left: the computer's prompt.
    static let prompt = [CGPoint(x: 128, y: 122), CGPoint(x: 222, y: 234), CGPoint(x: 128, y: 346)]
    /// "<" on the right: the phone.
    static let phone = [CGPoint(x: 384, y: 122), CGPoint(x: 290, y: 234), CGPoint(x: 384, y: 346)]
    /// The underscore, a rounded bar.
    static let cursor = CGRect(x: 300, y: 398, width: 84, height: 26)
    static let cursorRadius: CGFloat = 8
    /// The thin light line just inside the square's edge.
    static let border = CGRect(x: 2, y: 2, width: 508, height: 508)
    static let borderRadius: CGFloat = 112
    static let borderWidth: CGFloat = 3
    /// The faint mint light inside the square: its centre, and its radius as a part of the side.
    static let innerGlowCenter = UnitPoint(x: 0.42, y: 0.46)
    static let innerGlowRadius: CGFloat = 0.42

    /// The square, top to bottom.
    static let background = [color(0x1C1438), color(0x0B0716)]
    static let mint = [color(0x7DF7BE), color(0x2FD98A)]
    static let lilac = [color(0xFFFFFF), color(0xCFC8EE)]
    static let glow = color(0x4AF2A1)

    /// The halo's colours around the logo, `0xRRGGBB`: the brand's soft tones, mint, blue, violet, pink and amber,
    /// and mint again so that the turn has no seam.
    static let haloPalette: [UInt32] = [0x4AF2A1, 0x60A5FA, 0xA78BFA, 0xF472B6, 0xFBBF24, 0x4AF2A1]
    static let haloColors = haloPalette.map(color)
    /// How far the halo's shape reaches past the square's edge before it starts to fade, as a part of the logo's
    /// side: at the edge itself the halo is at four fifths of its strength.
    static let haloSpread: CGFloat = 0.06
    /// How softly the halo fades: the blur of its shape, as a part of the logo's side.
    static let haloSoftness: CGFloat = 0.07
    /// The halo's width across, as a part of the logo's side: the shape and its fade, which is gone 2.4 times the
    /// blur further out. It keeps the reach of the mint glow it replaced as far as the title allows: some 22 points
    /// round a 96-point logo, gone before the title's letters, which begin 24 points under it. On the left it meets
    /// the screen's edge, 16 points away, faintly, as the mint glow did.
    static let haloExtent: CGFloat = 1 + 2 * (haloSpread + 2.4 * haloSoftness)
    /// The side of the square of turning colours the halo is cut from, as a part of the logo's side: large enough
    /// to cover the halo out to its corners however far it has turned.
    static let haloField: CGFloat = 1.75

    static let promptGradient = gradient(mint, over: prompt, from: .topLeading, to: .bottomTrailing)
    static let phoneGradient = gradient(lilac, over: phone, from: .topTrailing, to: .bottomLeading)
    static let cursorGradient = gradient(mint, in: cursor, from: .topLeading, to: .bottomTrailing)

    /// The line a gradient runs along in the square, when the drawing gives it from `from` to `to` in the unit
    /// square of `box` (SVG's `objectBoundingBox`, the box of the shape without its stroke). In a box that is not
    /// square such a gradient is squeezed with the box, so its colours do not run along the box's diagonal: the
    /// result is the line, from the same starting corner, along which they do.
    static func gradientAxis(in box: CGRect, from: UnitPoint, to: UnitPoint) -> (start: CGPoint, end: CGPoint) {
        let start = CGPoint(x: box.minX + from.x * box.width, y: box.minY + from.y * box.height)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = dx * dx + dy * dy
        guard length > 0, box.width > 0, box.height > 0 else { return (start, start) }
        // The colour at a point is a·(x − start.x) + b·(y − start.y), 0 at the start and 1 at the end.
        let a = dx / (box.width * length)
        let b = dy / (box.height * length)
        let scale = 1 / (a * a + b * b)
        return (start, CGPoint(x: start.x + a * scale, y: start.y + b * scale))
    }

    /// The box around `points`.
    static func box(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() else { return .zero }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func gradient(_ colors: [Color], over points: [CGPoint], from: UnitPoint, to: UnitPoint) -> LinearGradient {
        gradient(colors, in: box(of: points), from: from, to: to)
    }

    /// A gradient for a shape that fills the whole square: its unit points are the square's.
    private static func gradient(_ colors: [Color], in box: CGRect, from: UnitPoint, to: UnitPoint) -> LinearGradient {
        let axis = gradientAxis(in: box, from: from, to: to)
        return LinearGradient(
            colors: colors, startPoint: UnitPoint(x: axis.start.x / side, y: axis.start.y / side),
            endPoint: UnitPoint(x: axis.end.x / side, y: axis.end.y / side))
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// A line through `points`, given in the mark's units and scaled to the rect it is drawn in.
struct SignInMarkLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / SignInLogoMark.side
        var path = Path()
        path.addLines(points.map { CGPoint(x: rect.minX + $0.x * unit, y: rect.minY + $0.y * unit) })
        return path
    }
}

/// The mark's underscore.
struct SignInMarkCursor: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / SignInLogoMark.side
        let bar = SignInLogoMark.cursor
        return Path(
            roundedRect: CGRect(
                x: rect.minX + bar.minX * unit, y: rect.minY + bar.minY * unit, width: bar.width * unit, height: bar.height * unit),
            cornerRadius: SignInLogoMark.cursorRadius * unit, style: .circular)
    }
}

/// The line just inside the square's edge.
struct SignInMarkBorder: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / SignInLogoMark.side
        let line = SignInLogoMark.border
        return Path(
            roundedRect: CGRect(
                x: rect.minX + line.minX * unit, y: rect.minY + line.minY * unit, width: line.width * unit,
                height: line.height * unit),
            cornerRadius: SignInLogoMark.borderRadius * unit, style: .circular)
    }
}
