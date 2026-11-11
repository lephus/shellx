import ShellXAppCore
import SwiftUI
import UIKit

/// The six-digit field with the failure under it; shared by the sign-in screen and the deletion sheet. It always
/// shows `model.code`: a seventh digit or a letter never stays, and a pasted "123 456" becomes the six digits.
///
/// It takes the keyboard when it appears and each time it can be typed in again (a new code was sent after the last
/// one stopped working). It is never turned off while a request runs, so the keyboard stays up through a wrong code;
/// what is typed then is simply not taken.
struct EmailCodeField: View {
    let model: EmailSignInModel
    let label: LocalizedStringResource
    var id = "signin.email.code"
    var errorID = "signin.email.error"

    /// A new value puts the keyboard in the field.
    @State private var focusRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OneTimeCodeTextField(
                model: model, code: model.code, placeholder: String(localized: label), id: id, focusRequest: focusRequest
            )
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
            .disabled(!model.codeIsLive)
            .onChange(of: model.codeIsLive) { _, live in
                if live { focusRequest += 1 }
            }
            .onAppear {
                if model.codeIsLive { focusRequest += 1 }
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
}

/// The UIKit field under `EmailCodeField`. Each edit goes to the model and what the model kept is written back in
/// the same call, so no edit can slip between a write-back and the next keystroke (a SwiftUI text binding lost one
/// that way). Number pad, one-time-code content type (iOS offers the code from Mail), monospaced digits, centred.
struct OneTimeCodeTextField: UIViewRepresentable {
    let model: EmailSignInModel
    /// `model.code`, read by the parent so that a change from the model (a wrong code empties it) updates the field.
    let code: String
    let placeholder: String
    let id: String
    /// A new value puts the keyboard in the field.
    let focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.textAlignment = .center
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.model = model
        if field.text != code { field.text = code }
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.accessibilityIdentifier = id
        let category = UIContentSizeCategory(context.environment.dynamicTypeSize)
        let size = UIFont.preferredFont(forTextStyle: .title2, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)).pointSize
        field.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
        field.isEnabled = context.environment.isEnabled
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            // After this update has put the field in its window.
            Task { @MainActor in field.becomeFirstResponder() }
        }
    }

    /// As wide as offered, as high as one line of its font.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: field.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var model: EmailSignInModel
        var focusRequest = 0

        init(model: EmailSignInModel) { self.model = model }

        @objc func changed(_ field: UITextField) {
            model.setCode(field.text ?? "")
            if field.text != model.code { field.text = model.code }
        }
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
