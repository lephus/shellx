/// ShellX's selection tint for one accent color (spec §6.1, §6.2).
///
/// The selected session row and the focused pane's selected tab are painted
/// with a soft wash of the accent rather than a neutral block, so the eye
/// finds them at a glance. The sidebar composites the accent over
/// ``ShellXPalette/panel`` into an opaque fill; the tab bar draws the accent
/// at a low alpha over whatever the bar shows. Both soften while the window
/// is not key or the app is in the background.
///
/// ```swift
/// let tint = ShellXSelectionTint(accent: ShellXPalette.primary)
/// tint.sidebarFill(isEmphasized: true).hexString     // "#222d4e"
/// tint.tabFill(isWindowKey: true).hexStringWithAlpha // "#60a5fa29"
/// ```
///
/// Readability targets (selected names at 7:1, effect colors at 4.5:1) are
/// guaranteed for the default accent only. Another accent keeps its hue and
/// is not adjusted.
public struct ShellXSelectionTint: Hashable, Sendable {
    /// The accent the fills are drawn from. Only its RGB is used: each fill
    /// sets its own opacity.
    public let accent: ShellXColor

    /// Creates the tint for an accent.
    ///
    /// - Parameter accent: The app accent as a dark surface draws it, for
    ///   example ``ShellXPalette/primary``. Its alpha is ignored.
    public init(accent: ShellXColor) {
        self.accent = accent
    }

    /// The opaque fill behind the selected sidebar row.
    ///
    /// The accent at 22% over ``ShellXPalette/panel``, or 16% while the
    /// selection is not emphasized. The default accent gives `#222d4e`
    /// (about 1.4:1 against the sidebar) and `#1d2440`.
    ///
    /// - Parameter isEmphasized: Whether the app is active and the sidebar's
    ///   window is key; false gives the softer fill.
    /// - Returns: An opaque color.
    public func sidebarFill(isEmphasized: Bool) -> ShellXColor {
        accent.withAlpha(isEmphasized ? 0.22 : 0.16).composited(over: ShellXPalette.panel)
    }

    /// The opaque fill behind a row added to the selection with ⌘-click.
    ///
    /// The accent at 10% over ``ShellXPalette/panel``, or 18% with Increase
    /// Contrast. Lighter than the emphasized ``sidebarFill(isEmphasized:)``,
    /// so the focused row stays the clear anchor of a multi-selection.
    ///
    /// - Parameter increaseContrast: Whether the system Increase Contrast
    ///   setting is on.
    /// - Returns: An opaque color.
    public func multiSelectionFill(increaseContrast: Bool) -> ShellXColor {
        accent.withAlpha(increaseContrast ? 0.18 : 0.10).composited(over: ShellXPalette.panel)
    }

    /// The fill of the focused pane's selected tab.
    ///
    /// The accent at 16% alpha, or 12% while the window is not key. It is
    /// not composited, so the tab bar's own background shows through.
    ///
    /// - Parameter isWindowKey: Whether the tab bar's window is key.
    /// - Returns: The accent with the tab alpha.
    public func tabFill(isWindowKey: Bool) -> ShellXColor {
        accent.withAlpha(isWindowKey ? 0.16 : 0.12)
    }
}
