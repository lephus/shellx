import AppKit
import ShellXBrand
import ShellXRemoteCore
import ShellXRemoteUI
import SwiftUI

/// "Continue with Google" in the browser, then "Signed in as …". `.link` is the switch from a password
/// session. Dark panel, flat fills, 1 px borders; the Google button keeps Google's own Light look.
struct SignInSheet: View {
    let model: GoogleSignInModel

    private var title: String {
        switch model.purpose {
        case .signIn: String(localized: "remote.signin.title", defaultValue: "Sign in to ShellX")
        case .link: String(localized: "remote.signin.switch.title", defaultValue: "Switch to Google sign-in")
        }
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
            content
            if let errorText = model.errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(ShellXPalette.error.color)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isSignedIn {
                HStack {
                    Spacer(minLength: 0)
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                        model.cancel()
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

    private var isSignedIn: Bool {
        if case .signedIn = model.phase { return true }
        return false
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .ready:
            HStack {
                Spacer(minLength: 0)
                GoogleSignInButton(
                    title: String(localized: "remote.signin.google", defaultValue: "Continue with Google")
                ) { model.start() }
                Spacer(minLength: 0)
            }
        case .waiting:
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
        case .signedIn(let email):
            VStack(alignment: .leading, spacing: 12) {
                Text(String(
                    format: String(localized: "remote.signin.signedInAs", defaultValue: "Signed in as %@"),
                    email
                ))
                .font(.system(size: 12))
                .foregroundColor(ShellXPalette.text.color)
                .lineLimit(2)
                .truncationMode(.middle)
                HStack {
                    Spacer(minLength: 0)
                    Button(String(localized: "remote.signin.done", defaultValue: "Done")) {
                        model.finish()
                    }
                    .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

/// Primary: primarySoft fill, 1 px primaryLine border, primaryText.
/// Secondary: raise fill, 1 px border, text. No gradients or glows.
struct ShellXSheetButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = kind == .primary ? ShellXPalette.primarySoft : ShellXPalette.raise
        let stroke = kind == .primary ? ShellXPalette.primaryLine : ShellXPalette.border
        let text = kind == .primary ? ShellXPalette.primaryText : ShellXPalette.text
        return configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundColor(text.color)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(stroke.color, lineWidth: 1)
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

    private init() {}

    /// The sheet over the remote service's own sign-in (the fixture service in previews).
    func present(service: any ShellXRemoteServicing, preferredWindow: NSWindow? = nil) {
        present(
            model: GoogleSignInModel(
                purpose: .signIn, labels: .localized,
                signIn: { try await service.signInWithGoogle() },
                cancel: { await service.cancelGoogleSignIn() }
            ),
            preferredWindow: preferredWindow
        )
    }

    /// One sheet at a time: an open one is brought to front and `model` is dropped.
    func present(model: GoogleSignInModel, preferredWindow: NSWindow? = nil) {
        if let window = sheet?.window {
            (hostWindow ?? window).makeKeyAndOrderFront(nil)
            return
        }
        model.onFinished = { [weak self] _ in self?.dismiss() }
        let sheet = CloudSheetWindow(rootView: SignInSheet(model: model))
        let window = sheet.window
        window.styleMask = [.titled]
        window.title = model.purpose == .link
            ? String(localized: "remote.signin.switch.title", defaultValue: "Switch to Google sign-in")
            : String(localized: "remote.signin.title", defaultValue: "Sign in to ShellX")
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        self.model = model
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
    }
}
