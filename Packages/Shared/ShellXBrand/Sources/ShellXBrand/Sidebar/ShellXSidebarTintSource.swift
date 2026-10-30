import Foundation

/// Where the left sidebar's color comes from when it does not share the
/// terminal backdrop. Stored under the `sidebarTintSource` defaults key.
public enum ShellXSidebarTintSource: String, CaseIterable, Sendable {
    /// Never chosen: the rule from before the choice existed applies.
    case automatic
    /// A color taken from the terminal theme.
    case theme
    /// The user's own tint.
    case custom

    /// Whether the sidebar draws a color taken from the terminal theme.
    ///
    /// Before the choice existed, the sidebar followed the theme only while
    /// its tint was untouched: the `panel` color, opaque, with no light or
    /// dark override. ``automatic`` keeps that rule, so a tint the user
    /// changed back then stays theirs.
    public func followsTerminalTheme(
        tintHex: String,
        tintHexLight: String?,
        tintHexDark: String?,
        tintOpacity: Double
    ) -> Bool {
        switch self {
        case .theme:
            return true
        case .custom:
            return false
        case .automatic:
            return tintHexLight == nil
                && tintHexDark == nil
                && tintOpacity >= 0.999
                && tintHex.caseInsensitiveCompare(ShellXPalette.panel.hexString) == .orderedSame
        }
    }
}
