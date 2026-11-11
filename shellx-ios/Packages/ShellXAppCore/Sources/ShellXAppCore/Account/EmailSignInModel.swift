import Foundation

/// The language the relay writes the code mail in.
public enum EmailCodeLocale {
    /// "vi" for Vietnamese ("vi", "vi-VN", "VI"), "en" for anything else (spec §3).
    public static func relayValue(appLanguage: String) -> String {
        let language = appLanguage.lowercased()
        return language == "vi" || language.hasPrefix("vi-") || language.hasPrefix("vi_") ? "vi" : "en"
    }

    /// For the language the app shows: `Bundle.main.preferredLocalizations.first`.
    public static var current: String {
        relayValue(appLanguage: Bundle.main.preferredLocalizations.first ?? "")
    }
}
