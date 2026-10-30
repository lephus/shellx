public import AppKit
import CmuxFoundation
import ShellXBrand

/// Default sidebar tint values. ShellX: the opaque `panel` token
/// (`ShellXPalette.panel`, #100b1d). The sidebar does not match the terminal
/// background by default. Until the user picks their own tint, the sidebar
/// takes its color from the terminal theme (``themeTint(forTerminalBackground:rendered:)``),
/// which gives `panel` for the ShellX theme (spec §7.4). `ShellXSidebarTintSource`
/// decides which applies.
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

    /// The sidebar color for a terminal theme: one small step off what the
    /// terminal draws, so the sidebar takes the theme's color and still reads
    /// as its own surface. The ShellX theme keeps `panel`, recognized by its
    /// own background even when a translucent terminal draws it composited.
    /// Another dark theme is lifted 2% toward white, about ShellX's own `bg`
    /// to `panel` step; a light theme is pressed 3% toward black.
    ///
    /// - Parameters:
    ///   - background: The theme's background color.
    ///   - rendered: The opaque color the terminal draws: `background`
    ///     composited over the window base.
    public static func themeTint(forTerminalBackground background: NSColor, rendered: NSColor) -> NSColor {
        if background.hexString().caseInsensitiveCompare(ShellXPalette.bg.hexString) == .orderedSame {
            return ShellXPalette.panel.nsColor
        }
        let resolver = WindowChromeColorResolver()
        let step = resolver.readableColorScheme(for: rendered) == .dark
            ? NSColor.white.withAlphaComponent(0.02)
            : NSColor.black.withAlphaComponent(0.03)
        return resolver.compositedColor(step, over: rendered)
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
