import Foundation

/// The signed-in account as kept in the Keychain. The token is a bearer secret: descriptions and
/// the mirror leave it out.
public struct StoredSession: Codable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var userID: String
    public var deviceID: String
    public var token: String
    public var email: String

    public init(userID: String, deviceID: String, token: String, email: String) {
        self.userID = userID
        self.deviceID = deviceID
        self.token = token
        self.email = email
    }

    public var description: String { "StoredSession(user: \(userID), device: \(deviceID), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["userID": userID, "deviceID": deviceID, "token": "<redacted>"], displayStyle: .struct)
    }
}
