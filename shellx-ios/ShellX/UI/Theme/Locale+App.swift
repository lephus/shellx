import Foundation

extension Locale {
    /// The language the app's strings show in (not the region's), so numbers and durations put
    /// into a sentence match the words around them.
    static var app: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
