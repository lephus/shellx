import ShellXAppCore
import SwiftUI

/// The signed-in email, and (outside the demo) switch to Google for a password session, sign out, and delete the
/// account. Sign out and delete ask before they do anything.
struct AccountSection: View {
    let email: String
    let account: AccountActions?
    @State private var confirming = false
    @State private var signingOut = false
    @State private var switching = false
    @State private var switchError: String?
    @State private var deleteStep: DeleteAccountSheet.Step?

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

            if let account {
                if account.authMethod == .password {
                    Button(action: { switchToGoogle(account) }) {
                        HStack {
                            Text(LocalizedStringResource("settings.account.switchToGoogle"))
                            Spacer()
                            if switching { ProgressView() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .disabled(switching)
                    .accessibilityIdentifier("settings.switchToGoogle")
                    if let switchError {
                        Text(switchError)
                            .font(.callout)
                            .foregroundStyle(Color("StatusError"))
                            .accessibilityIdentifier("settings.switchError")
                    }
                }

                Button(role: .destructive) {
                    confirming = true
                } label: {
                    HStack {
                        Text(LocalizedStringResource("settings.account.signOut"))
                        Spacer()
                        if signingOut { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(signingOut)

                Button(role: .destructive) {
                    deleteStep = account.authMethod == .password ? .switchFirst : .confirm
                } label: {
                    Text(LocalizedStringResource("settings.account.delete"))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("settings.deleteAccount")
            }
        } header: {
            Text(LocalizedStringResource("settings.account.title"))
        } footer: {
            if account?.authMethod == .password {
                Text(LocalizedStringResource("settings.account.switchToGoogle.detail"))
            }
        }
        .alert(
            String(localized: "settings.account.signOut"), isPresented: $confirming
        ) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "settings.account.signOut"), role: .destructive) {
                guard !signingOut, let account else { return }
                signingOut = true
                Task {
                    await account.signOut()
                    signingOut = false
                }
            }
        } message: {
            Text(LocalizedStringResource("settings.account.signOut.confirm"))
        }
        .sheet(isPresented: Binding(get: { deleteStep != nil }, set: { if !$0 { deleteStep = nil } })) {
            if let account, let step = deleteStep {
                DeleteAccountSheet(
                    step: step,
                    delete: { delete(account) },
                    switchToGoogle: { switchFromSheet(account) },
                    close: { deleteStep = nil })
                    .interactiveDismissDisabled(step == .working)
            }
        }
    }

    private func switchToGoogle(_ account: AccountActions) {
        guard !switching else { return }
        switching = true
        switchError = nil
        Task {
            do { try await account.switchToGoogle() } catch {
                if let failure = error as? SignInError { switchError = SignInErrorText.message(for: failure) }
            }
            switching = false
        }
    }

    private func delete(_ account: AccountActions) {
        let previous = deleteStep ?? .confirm
        deleteStep = .working
        Task {
            do { try await account.deleteAccount() } catch {
                let failure = error as? SignInError ?? .server(code: "unknown")
                if let message = SignInErrorText.message(for: failure) {
                    deleteStep = .failed(message)
                } else {
                    deleteStep = previous
                }
            }
        }
    }

    private func switchFromSheet(_ account: AccountActions) {
        let previous = deleteStep ?? .switchFirst
        deleteStep = .working
        Task {
            do { try await account.switchToGoogle() } catch {
                let failure = error as? SignInError ?? .server(code: "unknown")
                if let message = SignInErrorText.message(for: failure) {
                    deleteStep = .failed(message)
                } else {
                    deleteStep = previous
                }
            }
        }
    }
}
