import SwiftUI

/// Settings: your Macs, the account, the appearance, the voice (when the mic is set up) and an About
/// section.
struct SettingsView: View {
    let email: String
    let signOut: () async -> Void

    @Environment(VoiceService.self) private var voice: VoiceService?

    var body: some View {
        List {
            Group {
                Section {
                    // The pushed screen is registered by `SignedInView`.
                    NavigationLink(value: HomeRoute.machines) {
                        Label(String(localized: "machines.title"), systemImage: "laptopcomputer")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("settings.machines")
                }
                AccountSection(email: email, signOut: signOut)
                AppearanceSection()
                if let voice { VoiceSection(service: voice) }
                AboutSection()
            }
            .listRowBackground(Color.appSurface)
        }
        .themedList()
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.large)
    }
}

#if DEBUG
#Preview {
    NavigationStack { SettingsView(email: "phu@example.com", signOut: {}) }
}
#endif
