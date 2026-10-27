import SwiftUI

/// The signed-in email and the sign-out button, which asks before it does anything.
struct AccountSection: View {
    let email: String
    let signOut: () async -> Void
    @State private var confirming = false

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: email)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } label: {
                Text(LocalizedStringResource("signin.email"))
            }
            .accessibilityElement(children: .combine)

            Button(role: .destructive) {
                confirming = true
            } label: {
                Text(LocalizedStringResource("settings.account.signOut"))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        } header: {
            Text(LocalizedStringResource("settings.account.title"))
        }
        .alert(
            String(localized: "settings.account.signOut"), isPresented: $confirming
        ) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "settings.account.signOut"), role: .destructive) {
                Task { await signOut() }
            }
        } message: {
            Text(LocalizedStringResource("settings.account.signOut.confirm"))
        }
    }
}
