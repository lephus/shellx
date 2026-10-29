import SwiftUI
import UIKit

/// Settings › Appearance: light, dark, or whatever the iPhone uses (the default). It is set on the
/// app's windows (`overrideUserInterfaceStyle`), so sheets, alerts and the keyboard follow it too,
/// and going back to "Match iPhone" takes effect at once.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "shellx.appearance"

    var id: Self { self }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .system: return LocalizedStringResource("settings.appearance.system")
        case .light: return LocalizedStringResource("settings.appearance.light")
        case .dark: return LocalizedStringResource("settings.appearance.dark")
        }
    }

    /// The stored choice; anything unknown is "Match iPhone".
    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .system
    }

    /// Sets the choice on every window of the app.
    @MainActor func apply(to application: UIApplication = .shared) {
        for case let scene as UIWindowScene in application.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}
