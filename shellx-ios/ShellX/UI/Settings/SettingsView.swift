import SwiftUI

/// Settings: the account, the voice (when the mic is set up) and an About section.
struct SettingsView: View {
    let email: String
    let signOut: () async -> Void

    @Environment(VoiceService.self) private var voice: VoiceService?

    var body: some View {
        List {
            AccountSection(email: email, signOut: signOut)
            if let voice { VoiceSection(service: voice) }
            AboutSection()
        }
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.large)
    }
}

#if DEBUG
#Preview {
    NavigationStack { SettingsView(email: "phu@example.com", signOut: {}) }
}
#endif
