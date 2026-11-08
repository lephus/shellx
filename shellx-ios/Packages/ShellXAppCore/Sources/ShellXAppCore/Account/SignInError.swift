import Foundation
import ShellXLinkAccount

public enum SignInError: Error, Equatable, Sendable {
    case invalidCredentials
    case rateLimited
    case network
    case server(code: String)
    /// The previous account's data could not be removed from this iPhone yet; nobody can sign in
    /// until it is.
    case localWipePending
    /// The user closed Google's or Apple's sheet: nothing to show.
    case cancelled
    /// The email belongs to a password account that must switch from a device that is still signed in.
    case switchFromSignedInDevice
    /// Switch to Google: the Google account's email belongs to another ShellX account.
    case emailInUse
    /// Switch to Google: the Google account is linked elsewhere, or this account has another Google account.
    case identityInUse
    /// Delete Account: the fresh sign-in was another account or too old.
    case reauthRequired
    /// This build cannot offer that provider (no Google client ID).
    case providerUnavailable
    /// Google or Apple did not finish the sign-in.
    case providerFailed
    /// Delete Account on a password session: switch to Google first.
    case switchToGoogleFirst

    /// Maps what the relay and the identity providers threw.
    init(_ error: Error) {
        switch error {
        case let RelayAPIError.http(status, code):
            switch (status, code) {
            case (401, "invalid_credentials"): self = .invalidCredentials
            case (401, "reauth_required"): self = .reauthRequired
            case (409, "switch_from_signed_in_device"): self = .switchFromSignedInDevice
            case (409, "email_in_use"): self = .emailInUse
            case (409, "identity_in_use"): self = .identityInUse
            case (429, _): self = .rateLimited
            default: self = .server(code: code)
            }
        case let provider as IdentityProviderError:
            switch provider {
            case .cancelled: self = .cancelled
            case .notConfigured: self = .providerUnavailable
            case .failed: self = .providerFailed
            }
        case RelayAPIError.badResponse:
            self = .server(code: "bad_response")
        case is URLError:
            self = .network
        default:
            self = .server(code: "unknown")
        }
    }
}
