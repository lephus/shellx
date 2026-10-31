import AppKit

/// Text colors for the ShellX sidebar headers: the brand name, the
/// "YOUR MACHINES" label and the machine names.
///
/// Each resolves against the appearance it is drawn in. A dark sidebar uses
/// ShellX's text tokens; a light one (a light terminal theme the sidebar
/// follows) uses the system label colors, as workspace rows do.
public enum ShellXSidebarText {
    /// Names: `textHi`, or `labelColor` on a light sidebar.
    public static var title: NSColor { adaptive(dark: ShellXPalette.textHi.nsColor, light: .labelColor) }

    /// Labels and notes: `muted`, or `secondaryLabelColor` on a light sidebar.
    public static var muted: NSColor { adaptive(dark: ShellXPalette.muted.nsColor, light: .secondaryLabelColor) }

    /// Actionable text, such as the sign-in row: `primaryText`, or
    /// `linkColor` on a light sidebar.
    public static var link: NSColor { adaptive(dark: ShellXPalette.primaryText.nsColor, light: .linkColor) }

    private static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
