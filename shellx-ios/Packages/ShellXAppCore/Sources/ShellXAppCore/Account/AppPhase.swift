import Foundation

public enum AppPhase: Equatable, Sendable {
    /// The session has not been read yet (or the Keychain is locked after a restart).
    case launching
    /// `expired` is true when the relay refused the stored token.
    case signedOut(expired: Bool)
    /// Sign in with Apple found no account: "Connect to Your Mac" runs (`AppCoordinator.appleLink`).
    case linkingApple
    case signedIn(email: String)
}
