import AppKit

/// ShellX ships a dark interface only (spec §7.4, "Chủ đề màu").
///
/// The app forces this appearance at launch and on every live appearance
/// apply, and stores ``forcedModeRawValue`` as its appearance mode so the
/// terminal theme side, SwiftUI color scheme and AppKit chrome all resolve
/// dark. The Light/Dark/System picker is hidden.
public enum ShellXAppearance {
    /// The one `NSApp.appearance` ShellX uses.
    public static let forcedAppearanceName: NSAppearance.Name = .darkAqua

    /// The `appearanceMode` user-defaults value matching
    /// ``forcedAppearanceName`` (cmux's `AppearanceMode.dark`).
    public static let forcedModeRawValue = "dark"

    /// The forced appearance object.
    public static var forcedAppearance: NSAppearance? {
        NSAppearance(named: forcedAppearanceName)
    }
}
