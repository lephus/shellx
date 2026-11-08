import Foundation

/// Why "Connect to Your Mac" ended without an account; shown once on the sign-in screen.
public enum SignInNotice: Equatable, Sendable { case appleLinkDenied, appleLinkExpired, appleLinkFailed }
