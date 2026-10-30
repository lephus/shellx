public import AppKit
import CmuxFoundation
import ShellXBrand

/// Default sidebar tint values. ShellX: the opaque `panel` token
/// (`ShellXPalette.panel`, #100b1d). The sidebar does not match the terminal
/// background by default. While the tint stays at this default, the sidebar
/// takes its color from the terminal theme (``themeTint(forTerminalBackground:)``),
/// which gives `panel` for the ShellX theme (spec §7.4).
public struct WindowChromeSidebarTintDefaults: Sendable {
    /// Default tint hex value.
    public let hex: String

    /// Default tint opacity.
    public let opacity: Double

    /// Whether the sidebar uses the terminal background instead of the tint
    /// when the user has not chosen. Mirrors the
    /// `sidebarAppearance.matchTerminalBackground` catalog default. ShellX:
    /// `false`, so the `panel` tint shows out of the box.
    public static let matchesTerminalBackground = false

    /// `ShellXPalette.panel` as an uppercase `#RRGGBB` string.
    public static let shellXPanelHex = ShellXPalette.panel.hexString.uppercased()

    /// Whether the sidebar tint settings are still the default, so the
    /// sidebar follows the terminal theme. A chosen hex, a light or dark
    /// override, or a lowered opacity is the user's own tint and wins.
    public static func followsTerminalTheme(
        tintHex: String,
        tintHexLight: String?,
        tintHexDark: String?,
        tintOpacity: Double
    ) -> Bool {
        tintHexLight == nil
            && tintHexDark == nil
            && tintOpacity >= 0.999
            && tintHex.caseInsensitiveCompare(shellXPanelHex) == .orderedSame
    }

    /// The sidebar color for an opaque terminal background: one small step
    /// off it, so the sidebar takes the theme's color and still reads as its
    /// own surface. The ShellX theme keeps `panel`. Another dark theme is
    /// lifted 2% toward white, about ShellX's own `bg` to `panel` step; a
    /// light theme is pressed 3% toward black.
    public static func themeTint(forTerminalBackground background: NSColor) -> NSColor {
        if background.hexString().caseInsensitiveCompare(ShellXPalette.bg.hexString) == .orderedSame {
            return ShellXPalette.panel.nsColor
        }
        let resolver = WindowChromeColorResolver()
        let step = resolver.readableColorScheme(for: background) == .dark
            ? NSColor.white.withAlphaComponent(0.02)
            : NSColor.black.withAlphaComponent(0.03)
        return resolver.compositedColor(step, over: background)
    }

    /// Creates sidebar tint defaults.
    public init(
        hex: String = WindowChromeSidebarTintDefaults.shellXPanelHex,
        opacity: Double = 1.0
    ) {
        self.hex = hex
        self.opacity = opacity
    }
}
