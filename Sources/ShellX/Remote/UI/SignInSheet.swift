import AppKit
import ShellXBrand
import ShellXRemoteUI
import SwiftUI

/// State behind the "Sign in to ShellX" sheet.
@MainActor
final class SignInSheetModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var errorText: String?
    @Published private(set) var isSubmitting = false

    /// Called with true after a successful sign-in, false on cancel.
    var onFinished: ((Bool) -> Void)?
    private let signIn: @MainActor (String, String) async throws -> Void

    init(signIn: @escaping @MainActor (String, String) async throws -> Void) {
        self.signIn = signIn
    }

    var canSubmit: Bool {
        !isSubmitting
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorText = nil
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password
        let signIn = signIn
        Task { @MainActor in
            do {
                try await signIn(email, password)
                self.isSubmitting = false
                self.onFinished?(true)
            } catch {
                self.isSubmitting = false
                self.errorText = SignInErrorMessage.text(for: error, labels: .localized)
            }
        }
    }

    func cancel() {
        onFinished?(false)
    }
}

/// Email, password, primary "Sign in"; a failure shows inline in the error
/// color. Dark only, flat fills, 1 px borders.
struct SignInSheet: View {
    @ObservedObject var model: SignInSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "remote.signin.title", defaultValue: "Sign in to ShellX"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ShellXPalette.textHi.color)
                .lineLimit(1)
                .truncationMode(.tail)
            TextField(
                String(localized: "remote.signin.email", defaultValue: "Email"),
                text: $model.email
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            SecureField(
                String(localized: "remote.signin.password", defaultValue: "Password"),
                text: $model.password
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { model.submit() }
            if let errorText = model.errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(ShellXPalette.error.color)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if model.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                    model.cancel()
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "remote.signin.submit", defaultValue: "Sign in")) {
                    model.submit()
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSubmit)
            }
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(ShellXPalette.panel.color)
        .environment(\.colorScheme, .dark)
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
    private var model: SignInSheetModel?

    private init() {}

    func present(service: any ShellXRemoteServicing, preferredWindow: NSWindow? = nil) {
        if let window = sheet?.window {
            (hostWindow ?? window).makeKeyAndOrderFront(nil)
            return
        }
        let model = SignInSheetModel { email, password in
            try await service.signIn(email: email, password: password)
        }
        model.onFinished = { [weak self] _ in self?.dismiss() }
        let sheet = CloudSheetWindow(rootView: SignInSheet(model: model))
        let window = sheet.window
        window.styleMask = [.titled]
        window.title = String(localized: "remote.signin.title", defaultValue: "Sign in to ShellX")
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
