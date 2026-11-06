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
    /// A default with no theme file is never shown. `environment` and
    /// `bundleResourceURL` locate the theme files.
    public static func singleThemeAppearanceSubstitute(
        rawThemeValue: String,
        preferredColorScheme: ColorSchemePreference,
        environment: [String: String],
        bundleResourceURL: URL?
    ) -> String? {
        singleThemeAppearanceSubstitute(
            rawThemeValue: rawThemeValue,
            preferredColorScheme: preferredColorScheme,
            environment: environment,
            bundleResourceURL: bundleResourceURL,
            defaultPair: CmuxTerminalThemePair(light: cmuxDefaultLightThemeName, dark: cmuxDefaultDarkThemeName)
        )
    }

    /// ``singleThemeAppearanceSubstitute(rawThemeValue:preferredColorScheme:environment:bundleResourceURL:)``
    /// with the default light and dark themes given by `defaultPair`.
    static func singleThemeAppearanceSubstitute(
        rawThemeValue: String,
        preferredColorScheme: ColorSchemePreference,
        environment: [String: String],
        bundleResourceURL: URL?,
        defaultPair: CmuxTerminalThemePair
    ) -> String? {
        let pair = CmuxManagedThemeBlock().themePair(fromRawValue: rawThemeValue)
        let fitted = pair.fillingUnsuitedSide(
            from: defaultPair,
            isDark: { themeIsDark(named: $0, environment: environment, bundleResourceURL: bundleResourceURL) }
        )
        let (shown, configured) = preferredColorScheme == .light
            ? (fitted.light, pair.light)
            : (fitted.dark, pair.dark)
        // A default with no theme file would leave Ghostty's built-in colors,
        // which is worse than the configured theme.
        guard let shown, shown != configured,
              themeFileExists(named: shown, environment: environment, bundleResourceURL: bundleResourceURL) else {
            return nil
        }
        return shown
    }

    /// Whether a theme file named `name` exists in any theme search path.
    static func themeFileExists(
        named name: String,
        environment: [String: String],
        bundleResourceURL: URL?
    ) -> Bool {
        themeNameCandidates(from: name).contains { candidateName in
            themeSearchPaths(
                forThemeName: candidateName,
                environment: environment,
                bundleResourceURL: bundleResourceURL
            ).contains { FileManager.default.isReadableFile(atPath: $0) }
        }
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
