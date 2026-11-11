import Foundation
import ShellXRemoteCore

/// Localized sign-in failures, injected so this module needs no bundle.
public struct SignInErrorLabels: Equatable, Sendable {
    public let credentials: String
    public let network: String
    public let timeout: String
    public let stateMismatch: String
    public let switchFromSignedInDevice: String
    public let emailInUse: String
    public let identityInUse: String
    public let browser: String
    /// The email path (``SignInErrorMessage/emailText(forCode:labels:)``): an address the relay refuses.
    public let invalidEmail: String
    /// The email path: a disposable address.
    public let disposableEmail: String
    /// The email path: a wrong code (the relay's 401).
    public let invalidCode: String
    /// The email path: a code that no longer works (the relay's 410).
    public let codeExpired: String
    /// The email path: the relay could not mail the code (502).
    public let emailSendFailed: String
    /// The email path: a relay without email sign-in (`email_sign_in_disabled`).
    public let unavailable: String
    /// The email path: too many requests (429).
    public let rateLimited: String
    /// The email path: any failure without a sentence of its own (a body-less 5xx among them).
    public let server: String

    public init(
        credentials: String, network: String, timeout: String, stateMismatch: String,
        switchFromSignedInDevice: String, emailInUse: String, identityInUse: String, browser: String,
        invalidEmail: String, disposableEmail: String, invalidCode: String, codeExpired: String,
        emailSendFailed: String, unavailable: String, rateLimited: String, server: String
    ) {
        self.credentials = credentials
        self.network = network
        self.timeout = timeout
        self.stateMismatch = stateMismatch
        self.switchFromSignedInDevice = switchFromSignedInDevice
        self.emailInUse = emailInUse
        self.identityInUse = identityInUse
        self.browser = browser
        self.invalidEmail = invalidEmail
        self.disposableEmail = disposableEmail
        self.invalidCode = invalidCode
        self.codeExpired = codeExpired
        self.emailSendFailed = emailSendFailed
        self.unavailable = unavailable
        self.rateLimited = rateLimited
        self.server = server
    }

    public static let english = SignInErrorLabels(
        credentials: "Google sign-in didn't work. Try again.",
        network: "Can't reach relay.shellx.pro",
        timeout: "Google sign-in timed out. Try again.",
        stateMismatch: "Sign-in didn't finish. Try again.",
        switchFromSignedInDevice: "This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings \u{203A} Account \u{203A} Switch to Google sign-in, then try again.",
        emailInUse: "Another ShellX account already uses this Google account's email. Choose a different Google account.",
        identityInUse: "This Google account already signs in to another ShellX account, or this account already uses another Google account.",
        browser: "Couldn't open your browser.",
        invalidEmail: "That doesn't look like an email address.",
        disposableEmail: "Temporary email addresses can't be used. Try another address.",
        invalidCode: "That code isn't right. Check the email and try again.",
        codeExpired: "That code no longer works. Send a new one.",
        emailSendFailed: "Couldn't send the email. Try again in a moment.",
        unavailable: "This way of signing in isn't available in this build.",
        rateLimited: "Try again in a few minutes.",
        server: "ShellX is having a problem. Try again later."
    )
}

/// The inline text the sign-in sheet shows for a failed attempt.
public enum SignInErrorMessage {
    /// The Google path: known codes read as sentences; any other code is shown as is.
    public static func text(forCode code: String, labels: SignInErrorLabels) -> String {
        switch code {
        case "invalid_credentials": return labels.credentials
        case "network": return labels.network
        case "google_timeout": return labels.timeout
        case "google_state_mismatch": return labels.stateMismatch
        case "switch_from_signed_in_device": return labels.switchFromSignedInDevice
        case "email_in_use": return labels.emailInUse
        case "identity_in_use": return labels.identityInUse
        case "browser_unavailable": return labels.browser
        default: return code
        }
    }

    /// A non-core error (the transport threw before the core answered) reads
    /// as a network failure.
    public static func text(for error: any Error, labels: SignInErrorLabels) -> String {
        guard let coreError = error as? ShellXCoreError else { return labels.network }
        return text(forCode: coreError.code, labels: labels)
    }

    /// The email path's sentence for a core code (D2). Every code without a sentence of its own reads as
    /// `labels.server`, so the email path never shows a raw code.
    ///
    /// - Parameters:
    ///   - code: The core's code: `invalid_email`, `disposable_email`, `invalid_code`, `code_expired`,
    ///     `email_send_failed`, `email_sign_in_disabled` (as `unavailable`), `rate_limited`,
    ///     `switch_from_signed_in_device` and `network` have their own sentences.
    ///   - labels: The localized sentences.
    /// - Returns: The sentence to show.
    public static func emailText(forCode code: String, labels: SignInErrorLabels) -> String {
        switch code {
        case "invalid_email": return labels.invalidEmail
        case "disposable_email": return labels.disposableEmail
        case "invalid_code": return labels.invalidCode
        case "code_expired": return labels.codeExpired
        case "email_send_failed": return labels.emailSendFailed
        case "email_sign_in_disabled": return labels.unavailable
        case "rate_limited": return labels.rateLimited
        case "switch_from_signed_in_device": return labels.switchFromSignedInDevice
        case "network": return labels.network
        default: return labels.server
        }
    }

    /// The email path's sentence for a thrown error. A non-core error (the transport threw before the core
    /// answered) reads as the network sentence.
    ///
    /// - Parameters:
    ///   - error: What the request threw.
    ///   - labels: The localized sentences.
    /// - Returns: The sentence to show.
    public static func emailText(for error: any Error, labels: SignInErrorLabels) -> String {
        guard let coreError = error as? ShellXCoreError else { return labels.network }
        return emailText(forCode: coreError.code, labels: labels)
    }

    /// The person (or the browser page) ended the flow: not an error to show.
    public static func isCancellation(_ error: any Error) -> Bool {
        (error as? ShellXCoreError)?.code == "google_cancelled"
    }
}
