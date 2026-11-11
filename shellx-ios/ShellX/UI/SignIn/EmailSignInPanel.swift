import ShellXAppCore
import SwiftUI

/// The top of the first sign-in screen: the email field, what is wrong with it, and Send code. Every row is full
/// width and 12 points from the next.
///
/// Send code is off until the field holds something that can be an address (ASCII only); while the address has a
/// letter outside ASCII the field says so, so a disabled button is never a riddle.
struct EmailEntryRows: View {
    @Bindable var model: EmailSignInModel
    /// A new value puts the keyboard in the field.
    let focusRequest: Int
    /// Off while Google or Apple signs in.
    let enabled: Bool
    let send: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            EmailAddressField(
                text: Binding(get: { model.email }, set: { text in
                    model.begin()
                    model.email = text
                }),
                placeholder: String(localized: "signin.email.field"), focusRequest: focusRequest, submit: send
            )
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
            .disabled(!enabled)

            if let failure = model.emailFieldError, let message = SignInErrorText.message(for: failure) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Color("StatusError"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("signin.email.error")
            }

            Button(action: send) {
                EmailBusyLabel(title: LocalizedStringResource("signin.email.send"), busy: model.step == .sending)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!enabled || !model.canSend)
            .accessibilityIdentifier("signin.email.send")
        }
    }
}

/// The label of a primary button that shows a spinner in its place while its request runs. The title stays the
/// accessibility label, so the button keeps its name while busy.
struct EmailBusyLabel: View {
    let title: LocalizedStringResource
    let busy: Bool

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .opacity(busy ? 0 : 1)
            if busy {
                ProgressView()
                    .tint(PrimaryButtonStyle.label)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }
}
