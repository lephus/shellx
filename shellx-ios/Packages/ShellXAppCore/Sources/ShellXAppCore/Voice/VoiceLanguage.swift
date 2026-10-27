import Foundation

/// The language the user speaks to the mic: Vietnamese or English (plan decision D8). By default
/// Vietnamese when the iPhone's preferred languages include it; the user's choice in Settings is
/// kept in `UserDefaults`.
public enum VoiceLanguage: String, Codable, CaseIterable, Sendable {
    case vietnamese = "vi-VN"
    case english = "en-US"

    /// Where the user's choice is kept.
    public static let defaultsKey = "shellx.voice.language"

    /// Vietnamese when any of `preferredLanguages` (BCP 47, e.g. `Locale.preferredLanguages`) is
    /// Vietnamese, otherwise English.
    public init(preferredLanguages: [String]) {
        let vietnamese = preferredLanguages.contains { identifier in
            identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased() == "vi"
        }
        self = vietnamese ? .vietnamese : .english
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// The user's choice, or the default for `preferredLanguages` when there is none (or it is not
    /// one of the cases).
    public static func saved(
        in defaults: UserDefaults, preferredLanguages: [String] = Locale.preferredLanguages
    ) -> VoiceLanguage {
        defaults.string(forKey: defaultsKey).flatMap(VoiceLanguage.init(rawValue:))
            ?? VoiceLanguage(preferredLanguages: preferredLanguages)
    }

    public func save(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
