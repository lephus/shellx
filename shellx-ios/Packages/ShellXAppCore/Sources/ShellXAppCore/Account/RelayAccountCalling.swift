import Foundation
import ShellXLinkAccount

/// The relay calls the account flow needs. `RelayAPI` is the real one; tests use a fake.
public protocol RelayAccountCalling: Sendable {
    func login(email: String, password: String, deviceName: String, clientKey: Data) async throws -> AccountSession
    func nonce() async throws -> String
    func signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data) async throws -> AccountSignIn
    func linkGoogle(idToken: String, nonce: String, token: String) async throws -> AccountSignIn
    func signInWithApple(
        identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data
    ) async throws -> AppleSignInResult
    /// Links an Apple ID without an account to the account of the Mac whose pairing code is `offerURI`.
    func linkApple(offerURI: String, linkToken: String, clientKey: Data) async throws -> AppleLinkApproval
    func deleteAccount(idToken: String, nonce: String, token: String) async throws
    /// Asks the relay to mail a 6-digit code to `email`; `locale` ("vi" or "en") is the language of the mail.
    func requestEmailCode(email: String, locale: String) async throws -> EmailChallenge
    func signInWithEmailCode(challengeID: String, code: String, deviceName: String, clientKey: Data) async throws -> AccountSignIn
    /// Deletes the account of an email session with a code mailed to its address.
    func deleteAccount(challengeID: String, code: String, token: String) async throws
    func logout(token: String) async throws
    func machines(token: String) async throws -> [PairedMachineListing]
    func unpair(grantID: String, token: String) async throws
    func pair(offerURI: String, clientKey: Data, token: String) async throws -> PairedMachine
    /// This phone's APNs token, hex, for the app `topic` on the APNs host `environment`.
    func setPushToken(_ hexToken: String, topic: String, environment: APNsEnvironment, token: String) async throws
}
