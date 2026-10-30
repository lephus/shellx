import AppKit

/// Text colors for the ShellX sidebar headers: the brand name, the
/// "YOUR MACHINES" label and the machine names.
public enum ShellXSidebarText {
    /// Names: `textHi`.
    public static var title: NSColor { ShellXPalette.textHi.nsColor }

    /// Labels and notes: `muted`.
    public static var muted: NSColor { ShellXPalette.muted.nsColor }

    /// Actionable text, such as the sign-in row: `primaryText`.
    public static var link: NSColor { ShellXPalette.primaryText.nsColor }
}
