import AppKit
import ShellXBrand
import ShellXRemoteCore
import ShellXRemoteUI
import SwiftUI

/// The email part of the sign-in sheet (D3). On the first screen it is the address field, its failure and Send code;
/// once a code was mailed, the code step takes their place. It draws nothing in `.done`, where the sheet shows
/// "Signed in as …".
///
/// Every text field and full-width button is ``contentWidth`` wide, so no control whose size depends on the offered
/// width can feed back into the sheet's size (`CloudSheetWindow`).
struct EmailSignInSection: View {
    /// The sheet's content width: 340 pt less 20 pt of padding on each side.
    static let contentWidth: CGFloat = 300

    let model: EmailSignInModel
    let google: GoogleSignInModel
    let onCancel: () -> Void

    /// Grows when the code field shows text the model did not keep (a letter, say). The model's digits did not
    /// change, so nothing else would redraw the field, and it would show the letter until the next digit.
    @State private var codeRedraws = 0

    /// - Parameters:
    ///   - model: The sheet's email model.
    ///   - google: The sheet's Google model, for the one-flow-at-a-time rules (`SignInSheetFlows`).
    ///   - onCancel: The sheet's Cancel, which Escape in either field also calls.
    init(model: EmailSignInModel, google: GoogleSignInModel, onCancel: @escaping () -> Void) {
        self.model = model
        self.google = google
        self.onCancel = onCancel
    }

    private var texts: EmailSignInTexts { .localized }

    var body: some View {
        if case .done = model.step {
            EmptyView()
        } else if let sentTo = model.sentTo {
            codeStep(sentTo: sentTo)
        } else {
            emailStep
        }
    }

    /// The address field, the sentence under it and Send code. All three are off while Google waits.
    private var emailStep: some View {
        let enabled = SignInSheetFlows.emailEnabled(google: google)
        return VStack(alignment: .leading, spacing: 12) {
            SignInTextField(
                text: model.email,
                placeholder: texts.field,
                contentType: .emailAddress,
                font: .systemFont(ofSize: 13),
                isEnabled: enabled && model.step == .email,
                focusRequest: model.focusRequest,
                onChange: { SignInSheetFlows.setEmail(google: google, email: model, text: $0) },
                onSubmit: { _ = SignInSheetFlows.sendCode(google: google, email: model) },
                onCancel: onCancel
            )
            .frame(width: Self.contentWidth)
            if let failure = SignInSheetFlows.emailFieldError(google: google, email: model) {
                Self.failureText(failure)
            }
            Self.primaryButton(
                texts.send, isBusy: model.step == .sending, isEnabled: enabled && model.canSend
            ) {
                _ = SignInSheetFlows.sendCode(google: google, email: model)
            }
        }
    }

    /// The address line, the code field, its failure, Verify, Resend and "Use a different email".
    private func codeStep(sentTo: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(texts.sentTo(sentTo))
                .font(.system(size: 12))
                .foregroundColor(ShellXPalette.text.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.contentWidth, alignment: .leading)
            let _ = codeRedraws
            SignInTextField(
                text: model.code,
                placeholder: texts.code,
                contentType: .oneTimeCode,
                font: .monospacedDigitSystemFont(ofSize: 15, weight: .regular),
                isEnabled: model.canEditCode,
                focusRequest: model.focusRequest,
                onChange: { raw in
                    model.setCode(raw)
                    if raw != model.code { codeRedraws &+= 1 }
                },
                onSubmit: { _ = model.submitCode() },
                onCancel: onCancel
            )
            .frame(width: Self.contentWidth)
            if let failure = model.errorText {
                Self.failureText(failure)
            }
            Self.primaryButton(texts.verify, isBusy: model.step == .verifying, isEnabled: model.canVerify) {
                _ = model.submitCode()
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let wait = model.resendWait(at: context.date)
                // VoiceOver: one name, the wait as the value, so the countdown does not rename it every second.
                Self.linkButton(
                    wait > 0 ? texts.resendIn(seconds: wait) : texts.resend,
                    spokenName: texts.resend,
                    spokenValue: wait > 0 ? Self.spokenWait(seconds: wait) : "",
                    isEnabled: wait == 0 && model.step == .code
                ) {
                    _ = model.resend()
                }
            }
            Self.linkButton(texts.change, isEnabled: model.step == .code) {
                model.useDifferentEmail()
            }
        }
    }

    /// A failure under its control: 11 pt in the error colour, every line of it. Four lines cut the German switch
    /// sentence (204 characters), whose end says what to do.
    /// VoiceOver hears it when it appears and when its text changes; a redraw with the same text says nothing.
    static func failureText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(ShellXPalette.error.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: contentWidth, alignment: .leading)
            .onChange(of: text, initial: true) { _, shown in
                announce(shown)
            }
    }

    /// Asks VoiceOver to read a failure that just appeared; never an empty one.
    private static func announce(_ failure: String) {
        guard !failure.isEmpty else { return }
        AccessibilityNotification.Announcement(failure).post()
    }

    /// The resend wait as VoiceOver reads it ("42 seconds"), in the app's language. Foundation formats it, so it
    /// needs no string of its own.
    static func spokenWait(seconds: Int) -> String {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.seconds], width: .wide).locale(Locale(identifier: language))
        )
    }

    /// A full-width primary button and the sheet's default action (Return), with a small spinner beside its title
    /// while its request runs.
    private static func primaryButton(
        _ title: String, isBusy: Bool, isEnabled: Bool, action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
        .keyboardShortcut(.defaultAction)
        .disabled(!isEnabled)
        .frame(width: contentWidth)
    }

    /// A text-only button on its own line, centred.
    /// A text-only button on its own line, centred. VoiceOver reads `spokenName` (the title when nil) and
    /// `spokenValue`.
    private static func linkButton(
        _ title: String, spokenName: String? = nil, spokenValue: String = "", isEnabled: Bool,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title).monospacedDigit()
        }
        .buttonStyle(ShellXSheetButtonStyle(kind: .link))
        .accessibilityLabel(spokenName ?? title)
        .accessibilityValue(spokenValue)
        .disabled(!isEnabled)
        .frame(width: contentWidth)
    }
}
