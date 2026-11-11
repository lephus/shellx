import Foundation
import ShellXLinkCore

/// A session the relay handed out for a Google, Apple or emailed-code sign-in, with the account's email.
/// The token is a bearer secret: descriptions and the mirror leave it and the email out.
public struct AccountSignIn: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public var session: AccountSession
    public var email: String

    public init(session: AccountSession, email: String) {
        self.session = session
        self.email = email
    }

    public var description: String {
        "AccountSignIn(user: \(session.userID), device: \(session.deviceID), <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self, children: ["userID": session.userID, "deviceID": session.deviceID], displayStyle: .struct)
    }
}

/// What the relay answers when it mails a code. `challengeID` signs in together with the mailed code, so descriptions
/// and the mirror leave it and the email out: "EmailChallenge(expiresIn: 600, resendIn: 60, <redacted>)".
public struct EmailChallenge: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public var challengeID: String
    /// Seconds until the code stops working.
    public var expiresIn: Int
    /// Seconds until another code may be asked for.
    public var resendIn: Int
    /// The address as the relay normalized it.
    public var email: String

    public init(challengeID: String, expiresIn: Int, resendIn: Int, email: String) {
        self.challengeID = challengeID
        self.expiresIn = expiresIn
        self.resendIn = resendIn
        self.email = email
    }

    public var description: String { "EmailChallenge(expiresIn: \(expiresIn), resendIn: \(resendIn), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["expiresIn": expiresIn, "resendIn": resendIn], displayStyle: .struct)
    }
}

public enum AppleSignInResult: Equatable, Sendable {
    case signedIn(AccountSignIn)
    case linkRequired(linkToken: String, expiresIn: Int)
}

public enum AppleLinkStatus: Equatable, Sendable {
    case pending, denied, expired
    case approved(AccountSignIn, machineID: String, name: String, linkSlot: String)
}

extension RelayAPI {
    /// A fresh single-use nonce for the next sign-in (`POST /v1/auth/nonce`).
    public func nonce() async throws -> String {
        let reply: NonceReply = try await send("POST", "/v1/auth/nonce", token: nil, body: [:])
        guard Self.isBase64URLSecret(reply.nonce) else { throw RelayAPIError.badResponse }
        return reply.nonce
    }

    /// What the relay hands out as a nonce or a challenge id: 1–128 base64url characters.
    private static func isBase64URLSecret(_ text: String) -> Bool {
        (1...128).contains(text.utf8.count)
            && text.utf8.allSatisfy {
                ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5a) || ($0 >= 0x61 && $0 <= 0x7a)
                    || $0 == 0x2d || $0 == 0x5f
            }
    }

    public func signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data)
        async throws -> AccountSignIn
    {
        let reply: SignInReply = try await send(
            "POST", "/v1/auth/google", token: nil,
            body: ["id_token": idToken, "nonce": nonce, "device": device(deviceName, clientKey)])
        return try reply.signIn()
    }

    public func linkGoogle(idToken: String, nonce: String, token: String) async throws -> AccountSignIn {
        let reply: SignInReply = try await send(
            "POST", "/v1/auth/google/link", token: token, body: ["id_token": idToken, "nonce": nonce])
        return try reply.signIn()
    }

    public func signInWithApple(
        identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data
    ) async throws -> AppleSignInResult {
        let reply: AppleReply = try await send(
            "POST", "/v1/auth/apple", token: nil,
            body: [
                "identity_token": identityToken, "authorization_code": authorizationCode, "nonce": nonce,
                "device": device(deviceName, clientKey),
            ])
        if reply.status == "link_required" {
            guard let linkToken = reply.linkToken, !linkToken.isEmpty, let expiresIn = reply.expiresIn
            else { throw RelayAPIError.badResponse }
            return .linkRequired(linkToken: linkToken, expiresIn: expiresIn)
        }
        guard reply.status == nil else { throw RelayAPIError.badResponse }
        return .signedIn(try SignInReply(reply).signIn())
    }

    /// Asks the Mac in `offer` to approve linking an Apple ID (`POST /v1/auth/apple/link`); returns the pairing id.
    public func requestAppleLink(linkToken: String, offer: PairingOffer, clientKey: Data) async throws -> String {
        let reply: AppleLinkCreated = try await send(
            "POST", "/v1/auth/apple/link", token: nil,
            body: [
                "link_token": linkToken, "machine_id": offer.machineID,
                "client_key_b64": clientKey.base64EncodedString(),
                "proof_b64": offer.proof(clientKey: clientKey).base64EncodedString(),
            ])
        guard Self.isSafeSegment(reply.pairingID) else { throw RelayAPIError.badResponse }
        return reply.pairingID
    }

    public func appleLinkStatus(linkToken: String, pairingID: String) async throws -> AppleLinkStatus {
        let reply: AppleLinkStatusReply = try await send(
            "POST", "/v1/auth/apple/link/status", token: nil,
            body: ["link_token": linkToken, "pairing_id": pairingID])
        switch reply.status {
        case "pending": return .pending
        case "denied": return .denied
        case "expired": return .expired
        case "approved":
            guard let session = reply.session, let machine = reply.machine else { throw RelayAPIError.badResponse }
            return .approved(
                try session.signIn(), machineID: machine.machineID, name: machine.name, linkSlot: machine.linkSlot)
        default: throw RelayAPIError.badResponse
        }
    }

    /// `DELETE /v1/account` with a fresh ID token of the account's identity.
    public func deleteAccount(idToken: String, nonce: String, token: String) async throws {
        let _: Empty = try await send(
            "DELETE", "/v1/account", token: token, body: ["id_token": idToken, "nonce": nonce])
    }

    /// Asks the relay to mail a 6-digit code to `email` (`POST /v1/auth/email/code`). The address goes as given: the
    /// relay normalizes it and answers with the address it mailed. `locale` is "vi" or "en", the language of the mail.
    public func requestEmailCode(email: String, locale: String) async throws -> EmailChallenge {
        let reply: EmailChallengeReply = try await send(
            "POST", "/v1/auth/email/code", token: nil, body: ["email": email, "locale": locale])
        guard Self.isBase64URLSecret(reply.challengeID), reply.expiresIn > 0, reply.resendIn >= 0, !reply.email.isEmpty
        else { throw RelayAPIError.badResponse }
        return EmailChallenge(
            challengeID: reply.challengeID, expiresIn: reply.expiresIn, resendIn: reply.resendIn, email: reply.email)
    }

    /// Signs in with the code mailed for `challengeID` (`POST /v1/auth/email/verify`). `code` goes as a string: a
    /// leading zero is part of it.
    public func signInWithEmailCode(challengeID: String, code: String, deviceName: String, clientKey: Data)
        async throws -> AccountSignIn
    {
        let reply: SignInReply = try await send(
            "POST", "/v1/auth/email/verify", token: nil,
            body: ["challenge_id": challengeID, "code": code, "device": device(deviceName, clientKey)])
        return try reply.signIn()
    }

    /// `DELETE /v1/account` with a code mailed to the account's address (an account that signs in by email).
    public func deleteAccount(challengeID: String, code: String, token: String) async throws {
        let _: Empty = try await send(
            "DELETE", "/v1/account", token: token, body: ["challenge_id": challengeID, "code": code])
    }

    private func device(_ name: String, _ clientKey: Data) -> [String: String] {
        ["kind": "mobile", "platform": "ios", "name": name, "public_key": Self.base64URL(clientKey)]
    }
}

// MARK: - Wire types

private struct NonceReply: Decodable { var nonce: String }

private struct EmailChallengeReply: Decodable {
    var challengeID: String
    var expiresIn: Int
    var resendIn: Int
    var email: String
    private enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case expiresIn = "expires_in"
        case resendIn = "resend_in"
        case email
    }
}

private struct SignInReply: Decodable {
    var userID: String?
    var deviceID: String?
    var token: String?
    var email: String?
    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case token, email
    }

    init(_ apple: AppleReply) {
        userID = apple.userID
        deviceID = apple.deviceID
        token = apple.token
        email = apple.email
    }

    func signIn() throws -> AccountSignIn {
        guard let userID, let deviceID, let token, let email else { throw RelayAPIError.badResponse }
        return AccountSignIn(session: AccountSession(userID: userID, deviceID: deviceID, token: token), email: email)
    }
}

private struct AppleReply: Decodable {
    var status: String?
    var linkToken: String?
    var expiresIn: Int?
    var userID: String?
    var deviceID: String?
    var token: String?
    var email: String?
    private enum CodingKeys: String, CodingKey {
        case status
        case linkToken = "link_token"
        case expiresIn = "expires_in"
        case userID = "user_id"
        case deviceID = "device_id"
        case token, email
    }
}

private struct AppleLinkCreated: Decodable {
    var pairingID: String
    private enum CodingKeys: String, CodingKey { case pairingID = "pairing_id" }
}

private struct AppleLinkStatusReply: Decodable {
    struct Machine: Decodable {
        var machineID: String
        var name: String
        var linkSlot: String
        private enum CodingKeys: String, CodingKey {
            case machineID = "machine_id"
            case name
            case linkSlot = "link_slot"
        }
    }
    var status: String
    var session: SignInReply?
    var machine: Machine?
}
