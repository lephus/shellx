import Foundation

/// The signed-in account as kept in the Keychain. The token is a bearer secret: descriptions and
/// the mirror leave it out.
/// How the stored session signed in; mirrors the relay's `tokens.auth_method`.
public enum AccountAuthMethod: String, Codable, Sendable { case password, google, apple }

public struct StoredSession: Codable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var userID: String
    public var deviceID: String
    public var token: String
    public var email: String
    public var authMethod: AccountAuthMethod

    public init(
        userID: String, deviceID: String, token: String, email: String, authMethod: AccountAuthMethod = .password
    ) {
        self.userID = userID
        self.deviceID = deviceID
        self.token = token
        self.email = email
        self.authMethod = authMethod
    }

    private enum CodingKeys: String, CodingKey {
        case userID, deviceID, token, email
        case authMethod = "auth_method"
    }

    /// A session stored before sign-in methods existed has no `auth_method`: it is a password session. An unknown
    /// value fails decoding, like any unreadable session.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(String.self, forKey: .userID)
        deviceID = try c.decode(String.self, forKey: .deviceID)
        token = try c.decode(String.self, forKey: .token)
        email = try c.decode(String.self, forKey: .email)
        authMethod = try c.decodeIfPresent(AccountAuthMethod.self, forKey: .authMethod) ?? .password
    }

    public var description: String { "StoredSession(user: \(userID), device: \(deviceID), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["userID": userID, "deviceID": deviceID, "token": "<redacted>"], displayStyle: .struct)
    }
}
