import ShellXAppCore

/// Google and Apple on the phone, through the system's sheets.
@MainActor
final class SystemIdentityProvider: IdentityProviding {
    private let googleClientID: String?
    private let apple = SystemAppleAuthorizer()

    /// `googleClientID` is Info.plist `ShellXGoogleClientID`; one that `GoogleOAuthClient` refuses makes Google throw
    /// `.notConfigured`.
    init(googleClientID: String?) {
        self.googleClientID = googleClientID
    }

    func googleIDToken(nonce: String) async throws -> String {
        guard let client = GoogleOAuthClient(clientID: googleClientID ?? "") else {
            throw IdentityProviderError.notConfigured
        }
        return try await GoogleSignIn(client: client, web: SystemWebAuthenticator()).idToken(nonce: nonce)
    }

    func appleCredential(requestNonce: String) async throws -> AppleCredential {
        try await apple.authorize(requestNonce: requestNonce)
    }
}
