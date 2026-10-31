import ShellXAppCore
import SwiftUI

/// The thin multicolor border that runs around an agent that waits for the user's answer: on a "Needs
/// you" card (`FocusRowView`) and on the chip of that agent's tab (`PaneChips`). Both use
/// `View.waitingBorder(isActive:cornerRadius:)`.
///
/// It is a 2-point ring in the shape's own corner radius, drawn over the view: it never covers or shifts
/// the text and takes no room. A conic gradient (blue, violet, pink, amber, blue) turns around the
/// shape once every 3 seconds at a constant speed. With Reduce Motion on, the ring stays as it is, still
/// in all its colours. The ring is decoration: it is hidden from VoiceOver, because the words on the
/// card and the chip ("Needs you") already say it. It is drawn only while `isActive`; otherwise there is
/// no view at all, so nothing runs.
///
/// What turns is the gradient square as a layer (a rotation), and the ring only masks it, so a frame
/// changes one transform and the gradient is never drawn again. `TimelineView(.animation)` ticks with the
/// display and stops with the scene.
struct WaitingBorder: View {
    /// The colours of the gradient, `0xRRGGBB`: the same at both ends, so the turn has no seam. Fixed in
    /// light and dark: the user chose a multicolor border for this one state.
    static let palette: [UInt32] = [0x60A5FA, 0xA78BFA, 0xF472B6, 0xFBBF24, 0x60A5FA]
    /// The ring's width in points.
    static let lineWidth: CGFloat = 2
    /// Seconds for one turn.
    static let turn: TimeInterval = 3

    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether an agent in `state` waits for the user's answer, and so gets the border. An agent whose
    /// Mac is not online shows as "Offline" and cannot be answered: no border.
    static func isActive(for state: AgentState, online: Bool = true) -> Bool {
        online && state == .needsInput
    }

    /// The gradient's turn, in degrees from 0 (inclusive) to 360, at `date`: constant speed, one turn
    /// per `turn` seconds, the same on every device and on every card, so two rings are never out of step.
    static func angle(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: turn)
        return (phase < 0 ? phase + turn : phase) / turn * 360
    }

    /// Whether the ring turns: not with Reduce Motion on.
    static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }

    var body: some View {
        Group {
            if Self.animates(reduceMotion: reduceMotion) {
                TimelineView(.animation) { context in ring(angle: Self.angle(at: context.date)) }
            } else {
                ring(angle: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The gradient at `angle`, seen through the ring. The gradient square is as wide as the shape's
    /// diagonal, so whatever its turn, it covers every corner.
    private func ring(angle: Double) -> some View {
        GeometryReader { proxy in
            let side = hypot(proxy.size.width, proxy.size.height)
            AngularGradient(colors: Self.palette.map(Self.color), center: .center)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(angle))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .mask {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black, lineWidth: Self.lineWidth)
        }
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Draws the waiting border (`WaitingBorder`) over this view while `isActive`, in a shape with
    /// `cornerRadius`, the corner radius of the view's own outline. Inactive, it adds nothing.
    func waitingBorder(isActive: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isActive { WaitingBorder(cornerRadius: cornerRadius) }
        }
    }
}
