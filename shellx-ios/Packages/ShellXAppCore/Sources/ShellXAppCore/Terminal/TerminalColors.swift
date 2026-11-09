import Foundation
import ShellXLinkCore

public struct TerminalRGB: Hashable, Sendable {
    public var red: UInt8, green: UInt8, blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// What a cell is drawn with, once its style is resolved against the palette.
public struct TerminalResolvedStyle: Hashable, Sendable {
    public var foreground: TerminalRGB
    /// Nil: the default background, which the canvas has painted already.
    public var background: TerminalRGB?
    public var bold: Bool, italic: Bool, underline: Bool, strike: Bool, overline: Bool
    /// False for `invisible`: only the background is drawn.
    public var drawsText: Bool
}

/// Styles and the palette of a frame (PROTOCOL.md 11.5) → colours.
public enum TerminalColors {
    private static let white = TerminalRGB(red: 255, green: 255, blue: 255)
    private static let black = TerminalRGB(red: 0, green: 0, blue: 0)

    /// "#rrggbb" in either case; nil otherwise.
    public static func rgb(_ hex: String) -> TerminalRGB? {
        let utf8 = Array(hex.utf8)
        guard utf8.count == 7, utf8[0] == UInt8(ascii: "#") else { return nil }
        var channels: [UInt8] = []
        for index in stride(from: 1, to: 7, by: 2) {
            guard let high = nibble(utf8[index]), let low = nibble(utf8[index + 1]) else { return nil }
            channels.append(high << 4 | low)
        }
        return TerminalRGB(red: channels[0], green: channels[1], blue: channels[2])
    }

    /// The palette's foreground, else #ffffff.
    public static func foreground(_ palette: TerminalPalette) -> TerminalRGB {
        rgb(palette.fg) ?? white
    }

    /// The palette's background, else #000000.
    public static func background(_ palette: TerminalPalette) -> TerminalRGB {
        rgb(palette.bg) ?? black
    }

    /// The palette's cursor, else the foreground.
    public static func cursor(_ palette: TerminalPalette) -> TerminalRGB {
        palette.cursor.flatMap(rgb) ?? foreground(palette)
    }

    public static func resolve(_ style: TerminalCellStyle, palette: TerminalPalette) -> TerminalResolvedStyle {
        var foreground = style.fgRgb.flatMap(rgb) ?? indexed(style.fg, palette: palette) ?? Self.foreground(palette)
        var background = style.bgRgb.flatMap(rgb) ?? indexed(style.bg, palette: palette)
        var resolved = TerminalResolvedStyle(
            foreground: foreground, background: background,
            bold: false, italic: false, underline: false, strike: false, overline: false, drawsText: true)
        for attribute in style.attrs {
            switch attribute {
            case .bold: resolved.bold = true
            case .italic: resolved.italic = true
            case .underline: resolved.underline = true
            case .strike: resolved.strike = true
            case .overline: resolved.overline = true
            case .invisible: resolved.drawsText = false
            case .faint, .inverse, .blink, .other: break
            }
        }
        if style.attrs.contains(.inverse) {
            let newForeground = background ?? Self.background(palette)
            background = foreground
            foreground = newForeground
        }
        if style.attrs.contains(.faint) {
            foreground = mix(foreground, background ?? Self.background(palette))
        }
        resolved.foreground = foreground
        resolved.background = background
        return resolved
    }

    // MARK: - Helpers

    private static func indexed(_ index: Int?, palette: TerminalPalette) -> TerminalRGB? {
        guard let index, (0...255).contains(index), palette.colors.indices.contains(index) else { return nil }
        return rgb(palette.colors[index])
    }

    /// Each channel halfway between `a` and `b`, rounded.
    private static func mix(_ a: TerminalRGB, _ b: TerminalRGB) -> TerminalRGB {
        func half(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(((Double(x) + Double(y)) / 2).rounded()) }
        return TerminalRGB(red: half(a.red, b.red), green: half(a.green, b.green), blue: half(a.blue, b.blue))
    }

    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
