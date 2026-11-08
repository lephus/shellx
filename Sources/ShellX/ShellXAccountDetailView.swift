import CmuxFoundation
import ShellXBrand
import ShellXRemoteCore
import SwiftUI

/// Settings › Account rows under the identity row: the switch to Google (password sessions), the account's
/// sign-in methods (an Apple ID can be removed) and the link to delete the account.
struct ShellXAccountDetailView: View {
    let account: ShellXAccount
    let onSwitchToGoogle: @MainActor () -> Void
    let openURL: @MainActor (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if account.identity?.usesPassword == true {
                row {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "remote.signin.switch.title", defaultValue: "Switch to Google sign-in"))
                            .cmuxFont(size: 13, weight: .medium)
                        Text(String(
                            localized: "remote.signin.switch.intro",
                            defaultValue: "ShellX now signs in with Google. Switching keeps this computer, your phones and your share links."
                        ))
                        .cmuxFont(size: 11)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button(String(localized: "remote.signin.switch.button", defaultValue: "Switch…")) {
                        onSwitchToGoogle()
                    }
                    .controlSize(.small)
                }
                Divider()
            }
            row {
                Text(String(localized: "settings.account.methods.title", defaultValue: "Sign-in methods"))
                    .cmuxFont(size: 13, weight: .medium)
                Spacer(minLength: 12)
            }
            ForEach(account.signInMethods) { method in
                methodRow(method)
            }
            if let code = account.signInMethodsErrorCode {
                row {
                    Text(String(
                        format: String(
                            localized: "settings.account.methods.error",
                            defaultValue: "Sign-in methods: something went wrong (%@)"
                        ),
                        code
                    ))
                    .cmuxFont(size: 11)
                    .foregroundColor(.secondary)
                    Spacer(minLength: 12)
                }
            }
            row {
                Button(String(localized: "settings.account.deleteAccount", defaultValue: "Delete Account…")) {
                    openURL(ShellXBrand.deleteAccountURL)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Spacer(minLength: 12)
            }
        }
        .task { await account.refreshSignInMethods() }
    }

    private func methodRow(_ method: AccountSignInMethod) -> some View {
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text(method.isApple
                    ? String(localized: "settings.account.methods.apple", defaultValue: "Apple ID")
                    : String(localized: "settings.account.methods.google", defaultValue: "Google account"))
                    .cmuxFont(size: 12, weight: .medium)
                Text(subtitle(method))
                    .cmuxFont(size: 11)
                    .foregroundColor(.secondary)
                if method.isApple, let device = method.linkedViaDeviceName {
                    Text(String(
                        format: String(localized: "settings.account.methods.addedFrom", defaultValue: "Added from %@"),
                        device
                    ))
                    .cmuxFont(size: 11)
                    .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 12)
            if method.isApple {
                Button(String(localized: "settings.account.methods.remove", defaultValue: "Remove")) {
                    Task { await account.removeSignInMethod(id: method.id) }
                }
                .controlSize(.small)
                .disabled(account.removingSignInMethodIDs.contains(method.id))
            }
        }
    }

    private func subtitle(_ method: AccountSignInMethod) -> String {
        if method.isApple && (method.isPrivateEmail || method.email.isEmpty) {
            return String(localized: "settings.account.methods.hiddenEmail", defaultValue: "Hidden email")
        }
        return method.email
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}
