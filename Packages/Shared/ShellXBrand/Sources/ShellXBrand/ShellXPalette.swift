import AppKit
import SwiftUI

public struct ShellXColor: Equatable, Sendable {
    private let hex: UInt32
    public let alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        self.hex = hex & 0xFFFFFF
        self.alpha = alpha
    }

    /// Lowercase "#rrggbb" (alpha is not encoded).
    public var hexString: String {
        let s = String(hex, radix: 16)
        return "#" + String(repeating: "0", count: 6 - s.count) + s
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
}
