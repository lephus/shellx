import Foundation

public enum AppPhase: Equatable, Sendable {
    /// The session has not been read yet (or the Keychain is locked after a restart).
    case launching
    /// `expired` is true when the relay refused the stored token.
    case signedOut(expired: Bool)
    case signedIn(email: String)
}
