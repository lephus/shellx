import ShellXAppCore
import SwiftUI

/// The confirmation of "Delete Account…": what is lost, one destructive button, and (for a password session) the way
/// to switch to Google first. For an account signed in with an emailed code, the button mails a code to the account's
/// address and the sheet asks for it (`init(code:close:)`).
struct DeleteAccountSheet: View {
    enum Step: Equatable { case confirm, switchFirst, working, failed(String) }

    let step: Step
    var delete: () -> Void = {}
    var switchToGoogle: () -> Void = {}
    var close: () -> Void = {}
    /// Delete Account for an email session: its steps come from this model, not from `step`.
    private var code: EmailSignInModel?

    init(
        step: Step, delete: @escaping () -> Void = {}, switchToGoogle: @escaping () -> Void = {}, close: @escaping () -> Void = {}
    ) {
        self.step = step
        self.delete = delete
        self.switchToGoogle = switchToGoogle
        self.close = close
    }

    /// Delete Account for an email session, driven by `code` (made by `AppCoordinator.makeDeleteAccountCode()`).
    init(code: EmailSignInModel, close: @escaping () -> Void) {
        step = .confirm
        self.code = code
        self.close = close
    }

    private var isWorking: Bool { step == .working }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityHidden(true)
                Text(LocalizedStringResource("settings.account.delete.title"))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let code {
                    codeSteps(code)
                } else {
                    steps
                }
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        // A keyboard comes up for the code: the whole height.
        .presentationDetents(code == nil ? [.medium, .large] : [.large])
    }

    /// The sheet of a password, Google or Apple session, as `step` says.
    @ViewBuilder private var steps: some View {
        Text(step == .switchFirst
            ? LocalizedStringResource("settings.account.delete.switchFirst")
            : LocalizedStringResource("settings.account.delete.message"))
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        if case let .failed(message) = step {
            Text(message)
                .font(.callout)
                .foregroundStyle(Color("StatusError"))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("deleteAccount.error")
        }
        if isWorking {
            HStack(spacing: 8) {
                ProgressView()
                Text(LocalizedStringResource("settings.account.delete.deleting"))
            }
            .accessibilityElement(children: .combine)
        }
        if step == .switchFirst {
            Button(action: switchToGoogle) {
                Text(LocalizedStringResource("settings.account.switchToGoogle"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier("deleteAccount.switch")
        } else {
            Button(action: delete) {
                Text(LocalizedStringResource("settings.account.delete.button"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SecondaryButtonStyle(color: Color("StatusError")))
            .disabled(isWorking)
            .accessibilityIdentifier("deleteAccount.delete")
        }
        Button(action: close) {
            Text(LocalizedStringResource("common.cancel"))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(isWorking)
        .accessibilityIdentifier("deleteAccount.cancel")
    }

    // MARK: - Delete Account for an email session

    /// First what is lost and Delete Account, which mails the code; then the code field. Only the Delete Account
    /// button under the field deletes: the sixth digit never does.
    @ViewBuilder
    private func codeSteps(_ code: EmailSignInModel) -> some View {
        if code.panel == .code {
            Text(LocalizedStringResource("settings.account.delete.codeIntro"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            EmailCodeField(
                model: code, label: LocalizedStringResource("settings.account.delete.codeField"), id: "deleteAccount.code",
                errorID: "deleteAccount.error")
            if code.step == .verifying {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(LocalizedStringResource("settings.account.delete.deleting"))
                }
                .accessibilityElement(children: .combine)
            }
            deleteButton(busy: false) { Task { await code.verify() } }
                .disabled(!code.canVerify)
            EmailResendButton(model: code)
        } else {
            Text(LocalizedStringResource("settings.account.delete.message"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let error = code.error, let message = SignInErrorText.message(for: error) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Color("StatusError"))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("deleteAccount.error")
            }
            deleteButton(busy: code.step == .sending) { Task { await code.sendCode() } }
                .disabled(code.isBusy || !code.canSend)
        }
        Button(action: close) {
            Text(LocalizedStringResource("common.cancel"))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(code.isBusy)
        .accessibilityIdentifier("deleteAccount.cancel")
    }

    /// The destructive Delete Account button, with a spinner in place of its title while `busy`.
    private func deleteButton(busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(LocalizedStringResource("settings.account.delete.button"))
                    .font(.headline)
                    .opacity(busy ? 0 : 1)
                if busy {
                    ProgressView()
                        .tint(Color("StatusError"))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LocalizedStringResource("settings.account.delete.button")))
        }
        .buttonStyle(SecondaryButtonStyle(color: Color("StatusError")))
        .accessibilityIdentifier("deleteAccount.delete")
    }
}
