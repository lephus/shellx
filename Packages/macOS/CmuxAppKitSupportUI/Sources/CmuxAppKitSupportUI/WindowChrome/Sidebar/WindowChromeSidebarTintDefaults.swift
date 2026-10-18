import ShellXBrand

/// Default sidebar tint values. ShellX: the opaque `panel` token
/// (`ShellXPalette.panel`, #100b1d), drawn whenever the sidebar does not
/// match the terminal background.
public struct WindowChromeSidebarTintDefaults: Sendable {
    /// Default tint hex value.
    public let hex: String

    /// Default tint opacity.
    public let opacity: Double

    /// Whether the sidebar uses the terminal background instead of the tint
    /// when the user has not chosen. Mirrors the
    /// `sidebarAppearance.matchTerminalBackground` catalog default.
    public static let matchesTerminalBackground = true

    /// `ShellXPalette.panel` as an uppercase `#RRGGBB` string.
    public static let shellXPanelHex = ShellXPalette.panel.hexString.uppercased()

    /// Creates sidebar tint defaults.
    public init(
        hex: String = WindowChromeSidebarTintDefaults.shellXPanelHex,
        opacity: Double = 1.0
    ) {
        self.hex = hex
        self.opacity = opacity
    }
}
