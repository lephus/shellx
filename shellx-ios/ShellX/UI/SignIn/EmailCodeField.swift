import ShellXAppCore
import SwiftUI

/// The six-digit field with the failure under it; shared by the sign-in screen and the deletion sheet. It always
/// shows `model.code`: a seventh digit or a letter never stays, and a pasted "123 456" becomes the six digits.
///
/// It takes the keyboard when it appears and each time it can be typed in again (a new code was sent after the last
/// one stopped working). It is never turned off while a request runs, so the keyboard stays up through a wrong code;
/// what is typed then is simply not taken.
struct EmailCodeField: View {
    @Bindable var model: EmailSignInModel
    let label: LocalizedStringResource
    var id = "signin.email.code"
    var errorID = "signin.email.error"

    /// What the field holds. The model cuts it to its digits; what the model kept is written back here.
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(text: $text, prompt: Text(label)) { Text(label) }
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($focused)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
                .disabled(!model.codeIsLive)
                .accessibilityIdentifier(id)
                .onChange(of: text) { _, typed in
                    model.setCode(typed)
                    if text != model.code { text = model.code }
                }
                .onChange(of: model.code) { _, code in
                    if text != code { text = code }
                }
                .onChange(of: model.codeIsLive) { _, live in
                    if live { focus() }
                }
                .onAppear {
                    text = model.code
                    if model.codeIsLive { focus() }
                }
            if let error = model.error, let message = SignInErrorText.message(for: error) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Color("StatusError"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(errorID)
            }
        }
    }

    /// After this update: a field that has just appeared takes the focus only once it is in the window.
    private func focus() {
        Task { @MainActor in focused = true }
    }
}

/// "Resend code", or "Resend code in N s" while locked (monospaced digits, so the row does not move).
struct EmailResendButton: View {
    let model: EmailSignInModel

    var body: some View {
        Button {
            Task { await model.resend() }
        } label: {
            Group {
                if model.resendIn > 0 {
                    Text(LocalizedStringResource("signin.email.resendIn \(model.resendIn)"))
                } else {
                    Text(LocalizedStringResource("signin.email.resend"))
                }
            }
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(EmailTextButtonStyle())
        .disabled(!model.canResend)
        .accessibilityIdentifier("signin.email.resend")
    }
}

/// A text button of the email steps: the accent colour, faded to 40 % when it cannot be pressed.
struct EmailTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color("AccentText"))
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}
