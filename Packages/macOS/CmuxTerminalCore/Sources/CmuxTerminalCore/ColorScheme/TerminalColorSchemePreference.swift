public import Foundation
import ShellXBrand

/// The light/dark preference that drives terminal theme selection.
///
/// This is the terminal-domain home of what was `GhosttyConfig.ColorSchemePreference`.
/// It is the value libghostty theme resolution keys off of, distinct from the
/// app's broader appearance mode (which also carries `system`/`auto`). cmux
/// resolves the app appearance mode down to this two-case preference before
/// loading terminal colors.
public enum TerminalColorSchemePreference: Hashable, Sendable {
    case light
    case dark

    /// The persisted user-defaults key holding the app's appearance mode.
    /// Frozen wire-format key; reading it here keeps terminal theme resolution
    /// from reaching up into the app's appearance settings type.
    public static let appearanceModeDefaultsKey = "appearanceMode"

    /// Resolves the terminal color-scheme preference the way the app's
    /// appearance mode drives Ghostty split-theme selection: an explicit
    /// `light`/`dark` mode wins; `system` and `auto` follow the system
    /// interface style; an unset or unrecognized mode is the app's default
    /// mode (``ShellXAppearance/defaultModeRawValue``, Dark).
    ///
    /// This matches `AppearanceSettings.mode(for:)`, which collapses `auto` to
    /// `system` and unknown values to the default, so the terminal and the
    /// chrome never disagree about a missing or invalid stored value.
    public static func resolve(
        appearanceModeRawValue: String?,
        systemAppearance: TerminalSystemAppearance?,
        defaults: UserDefaults = .standard
    ) -> TerminalColorSchemePreference {
        let knownModes: Set<String> = ["light", "dark", "system", "auto"]
        let mode = appearanceModeRawValue.flatMap { knownModes.contains($0) ? $0 : nil }
            ?? ShellXAppearance.defaultModeRawValue
        switch mode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return (systemAppearance ?? .current(defaults: defaults)).prefersDark ? .dark : .light
        }
    }

    /// Reads the persisted appearance mode from the given defaults and resolves
    /// the terminal preference. The zero-config entry point used at config-load
    /// time.
    public static func current(
        defaults: UserDefaults = .standard,
        systemAppearance: TerminalSystemAppearance? = nil
    ) -> TerminalColorSchemePreference {
        resolve(
            appearanceModeRawValue: defaults.string(forKey: appearanceModeDefaultsKey),
            systemAppearance: systemAppearance,
            defaults: defaults
        )
    }
}
