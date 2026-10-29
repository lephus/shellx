import AppKit
import SwiftUI

public struct ShellXColor: Hashable, Sendable {
    private let hex: UInt32
    public let alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        self.hex = hex & 0xFFFFFF
        self.alpha = alpha
    }

    /// Reads an AppKit color, converting it to sRGB first.
    ///
    /// Each channel rounds to the nearest 8-bit step, so a palette color
    /// round-trips through ``nsColor`` unchanged. Dynamic colors resolve
    /// against the current drawing appearance. A color with no sRGB form
    /// (a pattern) reads as opaque black.
    ///
    /// - Parameter nsColor: The color to read, in any color space.
    public init(nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else {
            self.init(hex: 0)
            return
        }
        func byte(_ component: CGFloat) -> UInt32 {
            UInt32((min(max(Double(component), 0), 1) * 255).rounded())
        }
        self.init(
            hex: byte(srgb.redComponent) << 16 | byte(srgb.greenComponent) << 8 | byte(srgb.blueComponent),
            alpha: min(max(Double(srgb.alphaComponent), 0), 1)
        )
    }

    /// The same color at `alpha`.
    ///
    /// - Parameter alpha: The new opacity, clamped to `0...1`.
    /// - Returns: This color's RGB with the new alpha.
    public func withAlpha(_ alpha: Double) -> ShellXColor {
        ShellXColor(hex: hex, alpha: min(max(alpha, 0), 1))
    }

    /// This color painted over `base`, as an opaque color.
    ///
    /// Each 8-bit sRGB channel blends by this color's alpha, the way a CSS
    /// `rgba()` color does over a solid background, and rounds to the
    /// nearest step. `base` counts as opaque: its own alpha is ignored.
    ///
    /// ```swift
    /// // The selected sidebar row: primary at 22% over panel, #222d4e.
    /// let fill = ShellXPalette.primary.withAlpha(0.22).composited(over: ShellXPalette.panel)
    /// ```
    ///
    /// - Parameter base: The color underneath.
    /// - Returns: The blended color, with alpha 1.
    public func composited(over base: ShellXColor) -> ShellXColor {
        let coverage = min(max(alpha, 0), 1)
        func blend(_ shift: UInt32) -> UInt32 {
            let top = Double((hex >> shift) & 0xFF)
            let bottom = Double((base.hex >> shift) & 0xFF)
            return UInt32((top * coverage + bottom * (1 - coverage)).rounded())
        }
        return ShellXColor(hex: blend(16) << 16 | blend(8) << 8 | blend(0))
    }

    /// Lowercase "#rrggbb" (alpha is not encoded).
    public var hexString: String {
        let s = String(hex, radix: 16)
        return "#" + String(repeating: "0", count: 6 - s.count) + s
    }

    /// Lowercase "#rrggbbaa": ``hexString`` followed by the alpha as an
    /// 8-bit step (0.16 encodes as `29`, 1 as `ff`).
    public var hexStringWithAlpha: String {
        let alphaByte = String(UInt32((min(max(alpha, 0), 1) * 255).rounded()), radix: 16)
        return hexString + String(repeating: "0", count: 2 - alphaByte.count) + alphaByte
    }

    private var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    private var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    private var blue: Double { Double(hex & 0xFF) / 255 }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

public enum ShellXPalette {
    public static let bg = ShellXColor(hex: 0x0b0716)
    public static let panel = ShellXColor(hex: 0x100b1d)
    public static let raise = ShellXColor(hex: 0x171128)
    public static let line = ShellXColor(hex: 0x211a37)
    public static let border = ShellXColor(hex: 0x2a2145)
    public static let text = ShellXColor(hex: 0xcdc7e0)
    public static let textHi = ShellXColor(hex: 0xe6e2f2)
    public static let muted = ShellXColor(hex: 0x8a83a6)
    public static let primary = ShellXColor(hex: 0x60a5fa)
    public static let primarySoft = ShellXColor(hex: 0x60a5fa, alpha: 0.12)
    public static let primaryLine = ShellXColor(hex: 0x60a5fa, alpha: 0.45)
    public static let primaryText = ShellXColor(hex: 0x93c5fd)
    public static let running = ShellXColor(hex: 0xe8c468)
    public static let done = ShellXColor(hex: 0x6fd49a)
    public static let error = ShellXColor(hex: 0xe88a8a)

    // MARK: Selection (spec §6.1, §6.2)

    /// Session name on the selected sidebar row, over the tinted selection fill.
    public static let selectionTitle = ShellXColor(hex: 0xf1f5ff)
    /// Secondary text (metadata, status lines) on the selected sidebar row.
    public static let selectionSecondary = ShellXColor(hex: 0xb4c6e6)
    /// Fill behind an unselected sidebar row under the pointer: a muted
    /// violet, never the accent, so hover never reads as selection.
    public static let rowHover = ShellXColor(hex: 0x1b1530)
    /// Indicator under the selected tab of a pane that does not have focus.
    public static let unfocusedTabIndicator = ShellXColor(hex: 0x5b5478)
    /// Dark backing under a status pill's 12% fill on the selected row, so
    /// the pill keeps its contrast on the tinted selection.
    public static let selectionPillBacking = ShellXColor(hex: 0x0b0716, alpha: 0.55)
    /// Ring of the "waiting" pill on the selected row: brighter than
    /// ``primaryLine`` so the pill does not dissolve into the accent fill.
    public static let selectionWaitingRing = ShellXColor(hex: 0x93c5fd, alpha: 0.8)

    // MARK: Agent effects (spec §6.4)

    /// Name color while an agent works: a deep gold the highlight sweeps across.
    public static let effectWorkingBase = ShellXColor(hex: 0xb39550)
    /// Highlight that sweeps across a working name from left to right.
    public static let effectWorkingHighlight = ShellXColor(hex: 0xfff3cf)
    /// One-beat violet wash over the row or tab when a skill or workflow starts.
    public static let effectFlash = ShellXColor(hex: 0xd6c4ff, alpha: 0.26)
    /// Pastel stops a skill or workflow name cycles through, left to right.
    /// The first stop repeats at the end so the loop has no seam.
    public static let effectHighlightStops: [ShellXColor] = [
        ShellXColor(hex: 0xf4a7c0),
        ShellXColor(hex: 0xf2c879),
        ShellXColor(hex: 0x8fd9a8),
        ShellXColor(hex: 0x7cc8e8),
        ShellXColor(hex: 0x9fb0f5),
        ShellXColor(hex: 0xc9a7f2),
        ShellXColor(hex: 0xf4a7c0)
    ]
}
