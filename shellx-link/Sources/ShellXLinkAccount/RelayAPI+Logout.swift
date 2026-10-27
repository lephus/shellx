import Foundation

extension RelayAPI {
    /// Signs this phone out on the relay (`POST /v1/auth/logout`): the relay deletes the token and
    /// this device's push token. Any 2xx is success; anything else throws `RelayAPIError.http`.
    public func logout(token: String) async throws {
        let _: Empty = try await send("POST", "/v1/auth/logout", token: token, body: nil)
    }
}
