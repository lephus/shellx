import SwiftUI

/// Settings: the account and an About section.
struct SettingsView: View {
    let email: String
    let signOut: () async -> Void

    var body: some View {
        List {
            AccountSection(email: email, signOut: signOut)
            AboutSection()
        }
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { SettingsView(email: "phu@example.com", signOut: {}) }
}
