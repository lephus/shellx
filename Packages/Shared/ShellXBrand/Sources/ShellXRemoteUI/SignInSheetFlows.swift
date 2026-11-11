import Foundation

/// The email-first sheet's two flows (D3): one runs at a time, and only the last failure shows.
///
/// The sheet routes its actions through here instead of calling the two models directly:
///
/// ```swift
/// SignInSheetFlows.setEmail(google: google, email: email, text: newText)   // the email field changed
/// SignInSheetFlows.sendCode(google: google, email: email)                  // Send code or Return
/// SignInSheetFlows.startGoogle(google: google, email: email)               // Continue with Google
/// ```
@MainActor
public enum SignInSheetFlows {
    /// The email field and Send code take input: not while Google waits (nor after it signed in).
    ///
    /// - Parameter google: The sheet's Google model.
    /// - Returns: True when Google is ready.
    public static func emailEnabled(google: GoogleSignInModel) -> Bool {
        google.phase == .ready
    }

    /// Continue with Google can be pressed: Google `.ready`, and the email model (if any) on `.email`, so not while
    /// it sends, nor on the code step.
    ///
    /// - Parameters:
    ///   - google: The sheet's Google model.
    ///   - email: The sheet's email model; nil on the "Switch to Google sign-in" sheet.
    /// - Returns: True when the button is enabled.
    public static func googleEnabled(google: GoogleSignInModel, email: EmailSignInModel?) -> Bool {
        google.phase == .ready && (email?.step ?? .email) == .email
    }

    /// Send code: clears Google's failure, then `email.sendCode()`.
    ///
    /// - Parameters:
    ///   - google: The sheet's Google model.
    ///   - email: The sheet's email model.
    /// - Returns: The request's task; nil (and nothing cleared) unless ``emailEnabled(google:)`` holds and the
    ///   address can be sent.
    @discardableResult
    public static func sendCode(google: GoogleSignInModel, email: EmailSignInModel) -> Task<Void, Never>? {
        guard emailEnabled(google: google), email.canSend else { return nil }
        google.clearError()
        return email.sendCode()
    }

    /// Continue with Google: clears the email failure, then `google.start()`.
    ///
    /// - Parameters:
    ///   - google: The sheet's Google model.
    ///   - email: The sheet's email model; nil on the "Switch to Google sign-in" sheet.
    /// - Returns: The flow's task; nil (and nothing cleared) unless ``googleEnabled(google:email:)`` holds.
    @discardableResult
    public static func startGoogle(google: GoogleSignInModel, email: EmailSignInModel?) -> Task<Void, Never>? {
        guard googleEnabled(google: google, email: email) else { return nil }
        email?.clearError()
        return google.start()
    }

    /// The email field changed: `google.clearError()`, then `email.setEmail(text)`, so typing hides Google's failure.
    ///
    /// - Parameters:
    ///   - google: The sheet's Google model.
    ///   - email: The sheet's email model.
    ///   - text: The field's text.
    public static func setEmail(google: GoogleSignInModel, email: EmailSignInModel, text: String) {
        google.clearError()
        email.setEmail(text)
    }

    /// The sentence under the email field: nil while Google's failure shows, else `email.emailFieldError`. The
    /// invalid-email sentence of a non-ASCII address is computed from the text, so no start clears it.
    ///
    /// - Parameters:
    ///   - google: The sheet's Google model.
    ///   - email: The sheet's email model.
    /// - Returns: The sentence to draw, if any.
    public static func emailFieldError(google: GoogleSignInModel, email: EmailSignInModel) -> String? {
        google.errorText == nil ? email.emailFieldError : nil
    }
}
