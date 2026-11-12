import AppKit
import ShellXBrand
import ShellXRemoteCore
import ShellXRemoteUI
import SwiftUI

/// The "Sign in to ShellX" sheet, email first (D3): the email field and Send code, "or", Continue with Google, Cancel;
/// the code step after Send code; "Signed in as …" after either flow. `.link` (no email model) is the switch from a
/// password session: Google only, as before. Dark panel, flat fills, 1 px borders; the Google button keeps Google's
/// own Light look.
struct SignInSheet: View {
    let model: GoogleSignInModel
    /// The email path; nil on the "Switch to Google sign-in" sheet.
    let email: EmailSignInModel?

    private var title: String {
        switch model.purpose {
        case .signIn: String(localized: "remote.signin.title", defaultValue: "Sign in to ShellX")
        case .link: String(localized: "remote.signin.switch.title", defaultValue: "Switch to Google sign-in")
        }
    }

    private var googleTitle: String {
        String(localized: "remote.signin.google", defaultValue: "Continue with Google")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ShellXPalette.textHi.color)
                .lineLimit(1)
                .truncationMode(.tail)
            if model.purpose == .link {
                Text(String(
                    localized: "remote.signin.switch.intro",
                    defaultValue: "ShellX now signs in with Google. Switching keeps this computer, your phones and your share links."
                ))
                .font(.system(size: 12))
                .foregroundColor(ShellXPalette.text.color)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let email {
                emailFirst(email)
            } else {
                content
                googleFailure
            }
            if !isFinished {
                HStack {
                    Spacer(minLength: 0)
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                        cancel()
                    }
                    .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(ShellXPalette.panel.color)
        .environment(\.colorScheme, .dark)
    }

    /// Cancel, and Escape in either field: closes both flows. A request already sent is not stopped (Ruling 12), but
    /// no answer still on its way changes this sheet; the presenter's dismiss runs once.
    func cancel() {
        email?.cancel()
        model.cancel()
    }

    /// Either flow signed in: "Signed in as …" and Done show, Cancel does not.
    private var isFinished: Bool {
        if case .signedIn = model.phase { return true }
        if case .done = email?.step { return true }
        return false
    }

    /// The `.link` sheet's Google part, as it has always been: the button is the default action.
    @ViewBuilder private var content: some View {
        switch model.phase {
        case .ready:
            HStack {
                Spacer(minLength: 0)
                GoogleSignInButton(title: googleTitle) { model.start() }
                Spacer(minLength: 0)
            }
        case .waiting:
            waiting
        case .signedIn(let address):
            signedIn(address) { model.finish() }
        }
    }

    /// The `.signIn` sheet: the email part, then "or" and Google on the first screen.
    @ViewBuilder private func emailFirst(_ email: EmailSignInModel) -> some View {
        if case .signedIn(let address) = model.phase {
            signedIn(address) { model.finish() }
        } else if case .done(let address) = email.step {
            signedIn(address) { email.finish() }
        } else {
            EmailSignInSection(model: email, google: model, onCancel: { cancel() })
            if email.sentTo == nil {
                orLine
                if model.phase == .waiting {
                    waiting
                } else {
                    HStack {
                        Spacer(minLength: 0)
                        GoogleSignInButton(title: googleTitle, isDefaultAction: false) {
                            _ = SignInSheetFlows.startGoogle(google: model, email: email)
                        }
                        .disabled(!SignInSheetFlows.googleEnabled(google: model, email: email))
                        Spacer(minLength: 0)
                    }
                }
                googleFailure
            }
        }
    }

    /// "or", centred and muted, between two hairlines.
    private var orLine: some View {
        HStack(spacing: 8) {
            Rectangle().fill(ShellXPalette.border.color).frame(height: 1)
            Text(EmailSignInTexts.localized.or)
                .font(.system(size: 11))
                .foregroundColor(ShellXPalette.muted.color)
                .fixedSize()
            Rectangle().fill(ShellXPalette.border.color).frame(height: 1)
        }
        .frame(width: EmailSignInSection.contentWidth)
    }

    /// Google's failure, under its button.
    @ViewBuilder private var googleFailure: some View {
        if let errorText = model.errorText {
            EmailSignInSection.failureText(errorText)
        }
    }

    /// "Waiting for Google…" and its hint, in the Google button's place.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "remote.signin.waiting", defaultValue: "Waiting for Google…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ShellXPalette.textHi.color)
            }
            Text(String(
                localized: "remote.signin.browserHint",
                defaultValue: "Finish signing in in your browser, then come back here."
            ))
            .font(.system(size: 11))
            .foregroundColor(ShellXPalette.muted.color)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Signed in as …" and Done, the default action.
    private func signedIn(_ address: String, done: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(
                format: String(localized: "remote.signin.signedInAs", defaultValue: "Signed in as %@"),
                address
            ))
            .font(.system(size: 12))
            .foregroundColor(ShellXPalette.text.color)
            .lineLimit(2)
            .truncationMode(.middle)
            HStack {
                Spacer(minLength: 0)
                Button(String(localized: "remote.signin.done", defaultValue: "Done"), action: done)
                    .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Primary: primarySoft fill, 1 px primaryLine border, primaryText.
/// Secondary: raise fill, 1 px border, text. Link: primaryText alone, no fill or border.
/// No gradients or glows.
struct ShellXSheetButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, link }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        let stroke: Color
        let text: Color
        switch kind {
        case .primary:
            fill = ShellXPalette.primarySoft.color
            stroke = ShellXPalette.primaryLine.color
            text = ShellXPalette.primaryText.color
        case .secondary:
            fill = ShellXPalette.raise.color
            stroke = ShellXPalette.border.color
            text = ShellXPalette.text.color
        case .link:
            fill = .clear
            stroke = .clear
            text = ShellXPalette.primaryText.color
        }
        return configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundColor(text)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

/// Shows one sign-in sheet at a time on the main window, like
/// `CloudNetworkPolicySheetPresenter`.
@MainActor
final class SignInSheetPresenter {
    static let shared = SignInSheetPresenter()

    private var sheet: CloudSheetWindow?
    private var hostWindow: NSWindow?
    private var model: GoogleSignInModel?
    private var email: EmailSignInModel?

    private init() {}

    /// The sheet over the remote service's own sign-in (the fixture service in previews): email first, Google below.
    func present(service: any ShellXRemoteServicing, preferredWindow: NSWindow? = nil) {
        present(
            model: GoogleSignInModel(
                purpose: .signIn, labels: .localized,
                signIn: { try await service.signInWithGoogle() },
                cancel: { await service.cancelGoogleSignIn() }
            ),
            email: EmailSignInModel(
                labels: .localized,
                requestCode: { try await service.requestEmailCode(email: $0, locale: ShellXAccountFlow.emailLocale) },
                verify: { try await service.signInWithEmailCode(challengeID: $0, code: $1) }
            ),
            preferredWindow: preferredWindow
        )
    }

    /// One sheet at a time: an open one is brought to front and the new models are dropped. Either model closes the
    /// sheet when it finishes. `email` is nil for the "Switch to Google sign-in" sheet.
    func present(model: GoogleSignInModel, email: EmailSignInModel? = nil, preferredWindow: NSWindow? = nil) {
        if let window = sheet?.window {
            (hostWindow ?? window).makeKeyAndOrderFront(nil)
            return
        }
        model.onFinished = { [weak self] _ in self?.dismiss() }
        email?.onFinished = { [weak self] _ in self?.dismiss() }
        let sheet = CloudSheetWindow(rootView: SignInSheet(model: model, email: email))
        let window = sheet.window
        window.styleMask = [.titled]
        window.title = model.purpose == .link
            ? String(localized: "remote.signin.switch.title", defaultValue: "Switch to Google sign-in")
            : String(localized: "remote.signin.title", defaultValue: "Sign in to ShellX")
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        self.model = model
        self.email = email
        self.sheet = sheet

        let host = NSApp.cmuxMainWindowForModalPresentation(preferring: preferredWindow)
        if let host, host.attachedSheet == nil {
            hostWindow = host
            sheet.beginSheet(on: host)
        } else {
            hostWindow = nil
            sheet.orderFrontFloating()
        }
    }

    private func dismiss() {
        guard let window = sheet?.window else { return }
        if let host = hostWindow, host.attachedSheet === window {
            host.endSheet(window)
        }
        window.orderOut(nil)
        sheet = nil
        hostWindow = nil
        model = nil
        email = nil
    }
}
