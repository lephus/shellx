import CmuxFoundation
public import Foundation

extension GhosttyConfig {
    /// The theme to show in `preferredColorScheme` instead of the one
    /// `rawThemeValue` names, or `nil` when the value's own theme applies.
    ///
    /// A value naming one theme for both appearances only suits one of them
    /// (see ``CmuxTerminalThemePair/fillingUnsuitedSide(from:isDark:)``): a
    /// dark theme shows ``cmuxDefaultLightThemeName`` in light appearance, a
    /// light theme shows ``cmuxDefaultDarkThemeName`` in dark appearance.
    /// `environment` and `bundleResourceURL` locate the theme file that
    /// decides whether it is dark.
    public static func singleThemeAppearanceSubstitute(
        rawThemeValue: String,
        preferredColorScheme: ColorSchemePreference,
        environment: [String: String],
        bundleResourceURL: URL?
    ) -> String? {
        let pair = CmuxManagedThemeBlock().themePair(fromRawValue: rawThemeValue)
        let fitted = pair.fillingUnsuitedSide(
            from: CmuxTerminalThemePair(light: cmuxDefaultLightThemeName, dark: cmuxDefaultDarkThemeName),
            isDark: { themeIsDark(named: $0, environment: environment, bundleResourceURL: bundleResourceURL) }
        )
        let (shown, configured) = preferredColorScheme == .light
            ? (fitted.light, pair.light)
            : (fitted.dark, pair.dark)
        return shown == configured ? nil : shown
    }

    /// Whether the named theme's background is dark, from the first theme
    /// file found; `nil` when none is found or it sets no background.
    static func themeIsDark(
        named name: String,
        environment: [String: String],
        bundleResourceURL: URL?
    ) -> Bool? {
        let expanded = NSString(string: name).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return (try? String(contentsOfFile: expanded, encoding: .utf8))
                .flatMap { GhosttyThemeColors(parsing: $0).isDark }
        }
        for candidateName in themeNameCandidates(from: name) {
            for path in themeSearchPaths(
                forThemeName: candidateName,
                environment: environment,
                bundleResourceURL: bundleResourceURL
            ) {
                if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                    return GhosttyThemeColors(parsing: contents).isDark
                }
            }
        }
        return nil
    }
}
