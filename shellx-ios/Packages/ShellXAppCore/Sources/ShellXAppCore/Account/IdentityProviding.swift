import Foundation

public struct AppleCredential: Equatable, Sendable {
    public var identityToken: String
    public var authorizationCode: String

    public init(identityToken: String, authorizationCode: String) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
    }
}

public enum IdentityProviderError: Error, Equatable, Sendable {
    /// The user closed Google's or Apple's sheet.
    case cancelled
    /// This build has no usable Google client ID.
    case notConfigured
    /// Google or Apple did not finish: a bad redirect, another state, a refused code, a missing token.
    case failed
}

/// The phone's identity providers. The app implements it with AuthenticationServices; tests use a fake.
@MainActor public protocol IdentityProviding {
    /// Google's ID token for a sign-in carrying `nonce` (the relay's, raw).
    func googleIDToken(nonce: String) async throws -> String
    /// Sign in with Apple, `requestedScopes = [.email]`, with `requestNonce` = `AuthCrypto.sha256Hex(relay nonce)`.
    func appleCredential(requestNonce: String) async throws -> AppleCredential
}

/// Every call throws `IdentityProviderError.notConfigured` (the demo, tests that sign in no other way).
public struct UnavailableIdentityProvider: IdentityProviding {
    public init() {}
    public func googleIDToken(nonce: String) async throws -> String { throw IdentityProviderError.notConfigured }
    public func appleCredential(requestNonce: String) async throws -> AppleCredential {
        throw IdentityProviderError.notConfigured
    }
}
