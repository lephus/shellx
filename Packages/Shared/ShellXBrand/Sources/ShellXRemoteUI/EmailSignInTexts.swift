import Foundation

/// The email steps' texts, injected so this module needs no bundle (the app passes its localized texts).
///
/// ```swift
/// let texts = EmailSignInTexts.english
/// texts.resendIn(seconds: 42)   // "Resend code in 42 s"
/// ```
public struct EmailSignInTexts: Equatable, Sendable {
    /// The email field's placeholder ("Email address").
    public let field: String
    /// The button that mails a code ("Send code").
    public let send: String
    /// The line between the email part and Google ("or").
    public let or: String
    /// The code field's placeholder ("6-digit code").
    public let code: String
    /// The button that checks the code ("Verify").
    public let verify: String
    /// The resend button once its lock is over ("Resend code").
    public let resend: String
    /// The button back to the email step ("Use a different email").
    public let change: String
    /// The code step's first line; `%@` is the relay's address.
    public let sentToFormat: String
    /// The locked resend button; `%@` is the wait in whole seconds as text ("42"), not an integer placeholder.
    public let resendInFormat: String

    /// - Parameters:
    ///   - field: The email field's placeholder.
    ///   - send: The Send code button.
    ///   - or: The "or" line.
    ///   - sentToFormat: The code step's first line, with `%@` for the address.
    ///   - code: The code field's placeholder.
    ///   - verify: The Verify button.
    ///   - resend: The unlocked resend button.
    ///   - resendInFormat: The locked resend button, with `%@` for the whole seconds.
    ///   - change: The "Use a different email" button.
    public init(
        field: String, send: String, or: String, sentToFormat: String, code: String, verify: String,
        resend: String, resendInFormat: String, change: String
    ) {
        self.field = field
        self.send = send
        self.or = or
        self.sentToFormat = sentToFormat
        self.code = code
        self.verify = verify
        self.resend = resend
        self.resendInFormat = resendInFormat
        self.change = change
    }

    /// The English texts (the phone catalog's wording).
    public static let english = EmailSignInTexts(
        field: "Email address",
        send: "Send code",
        or: "or",
        sentToFormat: "We sent a 6-digit code to %@. If it isn't there in a minute, check your spam folder.",
        code: "6-digit code",
        verify: "Verify",
        resend: "Resend code",
        resendInFormat: "Resend code in %@ s",
        change: "Use a different email"
    )

    /// The code step's first line for `address`.
    ///
    /// - Parameter address: The relay's normalized address.
    /// - Returns: `sentToFormat` with the address in place of `%@`.
    public func sentTo(_ address: String) -> String {
        String(format: sentToFormat, address)
    }

    /// The locked resend button's text.
    ///
    /// - Parameter seconds: The whole seconds left.
    /// - Returns: `resendInFormat` with the seconds, as text, in place of `%@`.
    public func resendIn(seconds: Int) -> String {
        String(format: resendInFormat, String(seconds))
    }
}
