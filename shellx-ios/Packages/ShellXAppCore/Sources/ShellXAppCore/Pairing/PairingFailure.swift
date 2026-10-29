import Foundation
import ShellXLinkAccount
import ShellXLinkCore

/// Why pairing with a Mac did not work, as the pairing sheet tells it.
public enum PairingFailure: Equatable, Sendable {
    /// The text or QR code is not a `shellx-link://pair` code.
    case notShellXCode
    /// The code is from a newer ShellX (another `v`): this app needs an update.
    case needsUpdate
    /// A ShellX code with a missing or malformed field.
    case damagedCode
    /// The user pressed Deny on the Mac.
    case denied
    /// Nobody pressed Allow on the Mac in time.
    case expired
    /// The relay does not know the Mac under this account: it belongs to another one.
    case otherAccount
    /// The relay could not be reached.
    case network
    /// Anything else; `code` is the relay's error code (never a secret).
    case server(code: String)

    public init(_ error: any Error) {
        switch error {
        case PairingOfferError.badURI:
            self = .notShellXCode
        case PairingOfferError.unsupportedVersion:
            self = .needsUpdate
        case PairingOfferError.badField:
            self = .damagedCode
        case PhonePairingError.denied:
            self = .denied
        case PhonePairingError.expired:
            self = .expired
        case RelayAPIError.http(status: _, code: "machine_not_found"):
            self = .otherAccount
        case is URLError:
            self = .network
        case let RelayAPIError.http(status: _, code: code):
            self = .server(code: code)
        case RelayAPIError.badResponse:
            self = .server(code: "bad_response")
        case is SecretStoreError:
            self = .server(code: "keychain")
        case MachineHub.AddError.notSignedIn:
            self = .server(code: "signed_out")
        default:
            self = .server(code: "unknown")
        }
    }
}
