import Foundation

/// The APNs host a device token belongs to: Debug builds get sandbox tokens, App Store builds production.
public enum APNsEnvironment: String, Sendable {
    case sandbox
    case production
}

extension RelayAPI {
    /// Gives the relay this phone's APNs device token (`PUT /v1/devices/me/push-token`), so the Macs it
    /// paired with can reach it while the app is closed. `hexToken` is the token as lowercase hex, `topic`
    /// the app's bundle id. Sending the same token again is harmless; signing out deletes it.
    public func setPushToken(_ hexToken: String, topic: String, environment: APNsEnvironment, token: String) async throws {
        let body: [String: Any] = [
            "token": hexToken, "platform": "ios", "apns_topic": topic, "apns_env": environment.rawValue,
        ]
        let _: Empty = try await send("PUT", "/v1/devices/me/push-token", token: token, body: body)
    }
}
