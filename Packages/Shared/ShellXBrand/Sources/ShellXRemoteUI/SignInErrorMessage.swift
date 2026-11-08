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

    public init(
        credentials: String, network: String, timeout: String, stateMismatch: String,
        switchFromSignedInDevice: String, emailInUse: String, identityInUse: String, browser: String
    ) {
        self.credentials = credentials
        self.network = network
        self.timeout = timeout
        self.stateMismatch = stateMismatch
        self.switchFromSignedInDevice = switchFromSignedInDevice
        self.emailInUse = emailInUse
        self.identityInUse = identityInUse
        self.browser = browser
    }

    public static let english = SignInErrorLabels(
        credentials: "Google sign-in didn't work. Try again.",
        network: "Can't reach relay.shellx.pro",
        timeout: "Google sign-in timed out. Try again.",
        stateMismatch: "Sign-in didn't finish. Try again.",
        switchFromSignedInDevice: "This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings \u{203A} Account \u{203A} Switch to Google sign-in, then try again.",
        emailInUse: "Another ShellX account already uses this Google account's email. Choose a different Google account.",
        identityInUse: "This Google account already signs in to another ShellX account, or this account already uses another Google account.",
        browser: "Couldn't open your browser."
    )
}

/// The inline text the sign-in sheet shows for a failed attempt.
public enum SignInErrorMessage {
    /// Known codes read as sentences; any other code is shown as is.
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

    /// The person (or the browser page) ended the flow: not an error to show.
    public static func isCancellation(_ error: any Error) -> Bool {
        (error as? ShellXCoreError)?.code == "google_cancelled"
    }
}
