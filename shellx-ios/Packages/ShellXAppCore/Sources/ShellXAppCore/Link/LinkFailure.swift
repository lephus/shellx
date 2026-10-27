import Foundation
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkSession

/// Why a connection to a Mac failed, as far as the reconnect loop cares.
public enum LinkFailure: Equatable, Sendable {
    /// Network, relay or session trouble: try again later.
    case offline
    /// The relay refused the account token (401): the user must sign in again.
    case signedOut
    /// The Mac no longer lets this iPhone in (its grant is gone, or the Mac was removed).
    case revoked
    /// The Mac answered with another key than the one pinned at pairing.
    case hostKeyChanged
    /// The Mac speaks another protocol version: one of the two apps needs an update.
    case needsUpdate

    public init(_ error: any Error) {
        switch error {
        case RelayAPIError.http(status: 401, code: _):
            self = .signedOut
        case RelayAPIError.http(status: _, code: "not_granted"), RelayAPIError.http(status: _, code: "machine_not_found"):
            self = .revoked
        case NoiseError.untrustedPeer:
            self = .hostKeyChanged
        case LinkClientError.protocolMismatch:
            self = .needsUpdate
        default:
            self = .offline
        }
    }

    /// True when retrying cannot help, so the reconnect loop stops.
    public var stopsReconnecting: Bool { self != .offline }
}
