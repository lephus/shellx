import Foundation

/// A code the relay mailed: the id to verify it with and the address it went to (normalized by the relay).
///
/// Never logged: the challenge id and the address are secrets of the sign-in.
public struct EmailCodeChallenge: Equatable, Sendable {
    /// The id `auth.email.finish` verifies the code against.
    public let challengeID: String
    /// The address the relay mailed, trimmed and lowercased by the relay. Show it, not the typed text.
    public let email: String
    /// How long the code lives, in seconds (600).
    public let expiresIn: TimeInterval
    /// How long "Resend code" stays locked, in seconds (60).
    public let resendIn: TimeInterval

    /// - Parameters:
    ///   - challengeID: The id to verify the code against.
    ///   - email: The relay's normalized address.
    ///   - expiresIn: The code's life in seconds.
    ///   - resendIn: The resend lock in seconds.
    public init(challengeID: String, email: String, expiresIn: TimeInterval, resendIn: TimeInterval) {
        self.challengeID = challengeID; self.email = email; self.expiresIn = expiresIn; self.resendIn = resendIn
    }
}

/// Typed email-code sign-in calls. Every call blocks on the FFI: call from a background queue.
extension ShellXCoreClient {
    /// `auth.email.begin`: asks the relay to mail a 6-digit code to `email`. Writes nothing.
    ///
    /// - Parameters:
    ///   - email: The address as typed; the core trims it and refuses one outside ASCII without a request.
    ///   - locale: The UI language; the core sends `"vi"` for any value starting with `vi`, else `"en"`.
    /// - Returns: The challenge. `expiresIn` and `resendIn` fall back to 600 and 60 when the reply omits them.
    /// - Throws: The core's code (`invalid_email`, `disposable_email`, `rate_limited`, `email_send_failed`,
    ///   `email_sign_in_disabled`, `network`, …), or `bad_response` when the reply has no challenge id.
    public func beginEmailSignIn(email: String, locale: String) throws -> EmailCodeChallenge {
        struct Reply: Decodable { let challenge_id: String, email: String, expires_in: Double?, resend_in: Double? }
        let r = try call("auth.email.begin", ["email": .string(email), "locale": .string(locale)], as: Reply.self)
        guard !r.challenge_id.isEmpty else {
            throw ShellXCoreError(code: "bad_response", message: "core reply has no challenge id")
        }
        return EmailCodeChallenge(challengeID: r.challenge_id, email: r.email,
                                  expiresIn: r.expires_in ?? 600, resendIn: r.resend_in ?? 60)
    }

    /// `auth.email.finish`: verifies the code and, on success, writes the session (`auth_method: "email"`).
    ///
    /// - Parameters:
    ///   - challengeID: The id from ``beginEmailSignIn(email:locale:)``.
    ///   - code: The digits as typed; the core keeps six decimal digits as ASCII or answers `invalid_code`.
    /// - Returns: The account (never a token), in the shape of a finished Google flow.
    /// - Throws: The core's code (`invalid_code`, `code_expired`, `switch_from_signed_in_device`, `rate_limited`, …).
    public func finishEmailSignIn(challengeID: String, code: String) throws -> GoogleSignInResult {
        struct Reply: Decodable { let user_id: String, device_id: String, email: String, auth_method: String }
        let r = try call("auth.email.finish", ["challenge_id": .string(challengeID), "code": .string(code)], as: Reply.self)
        return GoogleSignInResult(userID: r.user_id, deviceID: r.device_id, email: r.email, authMethod: r.auth_method)
    }
}
