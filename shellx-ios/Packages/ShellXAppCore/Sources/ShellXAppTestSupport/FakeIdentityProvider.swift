import ShellXAppCore

/// An `IdentityProviding` answering from presets and recording what it was asked.
@MainActor public final class FakeIdentityProvider: IdentityProviding {
    public var googleResult: Result<String, Error> = .success("google-id-token")
    public var appleResult: Result<AppleCredential, Error> = .success(
        AppleCredential(identityToken: "apple-id-token", authorizationCode: "apple-code"))
    public private(set) var googleNonces: [String] = []
    public private(set) var appleRequestNonces: [String] = []

    public init() {}

    public func googleIDToken(nonce: String) async throws -> String {
        googleNonces.append(nonce)
        return try googleResult.get()
    }

    public func appleCredential(requestNonce: String) async throws -> AppleCredential {
        appleRequestNonces.append(requestNonce)
        return try appleResult.get()
    }
}
