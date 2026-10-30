import CmuxSettings

/// The three ways the left sidebar gets its background, offered as one
/// Settings choice. Stored as `sidebarAppearance.matchTerminalBackground`
/// plus `sidebarAppearance.tintSource`.
enum SidebarBackgroundChoice: Hashable, CaseIterable {
    /// A color taken from the terminal theme.
    case theme
    /// The terminal's own background color and transparency.
    case terminal
    /// The user's own color.
    case custom

    /// The choice the stored settings draw. An empty light or dark tint
    /// means no override is set.
    init(
        matchesTerminal: Bool,
        source: SidebarTintSourceOption,
        tintHex: String,
        tintHexLight: String,
        tintHexDark: String,
        tintOpacity: Double
    ) {
        if matchesTerminal {
            self = .terminal
        } else if source.followsTerminalTheme(
            tintHex: tintHex,
            tintHexLight: tintHexLight.isEmpty ? nil : tintHexLight,
            tintHexDark: tintHexDark.isEmpty ? nil : tintHexDark,
            tintOpacity: tintOpacity
        ) {
            self = .theme
        } else {
            self = .custom
        }
    }

    /// The `matchTerminalBackground` value that draws this choice.
    var matchesTerminal: Bool { self == .terminal }

    /// The `tintSource` value that draws this choice. Matching the terminal
    /// leaves the source alone, so turning it off restores the earlier pick.
    var tintSource: SidebarTintSourceOption? {
        switch self {
        case .theme: return .theme
        case .custom: return .custom
        case .terminal: return nil
        }
    }
}
