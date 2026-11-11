import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest
@testable import ShellXAppCore

/// The coordinator's side of sign-in with an emailed code, and of deleting the account of such a session.
@MainActor
final class AppCoordinatorEmailTests: XCTestCase {
    private func http(_ status: Int, _ code: String) -> RelayAPIError { .http(status: status, code: code) }

    /// A launched rig whose vault holds an email session with the token "tok-old".
    private func emailSession() async throws -> CoordinatorRig {
        let rig = await CoordinatorRig.make(self)
        try await rig.vault.setSession(
            StoredSession(userID: "u1", deviceID: "d1", token: "tok-old", email: "phu@example.com", authMethod: .email))
        try await rig.vault.setMachines([], owner: "u1")
        await rig.coordinator.launch()
        return rig
    }

    func testTheLocaleIsVietnameseOnlyForVietnamese() {
        XCTAssertEqual(
            ["vi", "vi-VN", "VI", "en", "fr", ""].map(EmailCodeLocale.relayValue(appLanguage:)),
            ["vi", "vi", "vi", "en", "en", "en"])
    }

    func testRequestingACodeSendsTheEmailInTheAppsLanguageAndStoresNothing() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.coordinator.launch()
        let challenge = try await rig.coordinator.requestEmailCode(email: "Phu@Example.com")
        XCTAssertEqual(challenge, EmailChallenge(challengeID: "challenge-1", expiresIn: 600, resendIn: 60, email: "phu@example.com"))
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.requestEmailCode(email: "Phu@Example.com", locale: "vi")])
        let session = try await rig.vault.session()
        XCTAssertNil(session)
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
    }

    func testTheRightCodeSignsInLikeGoogleWithAnEmailSession() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setEmailSignIn(
            .success(AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-e"), email: "phu@example.com")))
        try await rig.vault.setMachines(
            [PairedMachine(machineID: "m0", name: "Old", linkSlot: "s0", hostKey: Data(repeating: 1, count: 32))], owner: "someone-else")
        await rig.coordinator.launch()
        try await rig.coordinator.signInWithEmailCode(challengeID: "challenge-1", code: "012345")
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.signInWithEmailCode(challengeID: "challenge-1", code: "012345", deviceName: "Phu's iPhone", clientKey: key)])
        let session = try await rig.vault.session()
        XCTAssertEqual(session, StoredSession(userID: "u1", deviceID: "d1", token: "tok-e", email: "phu@example.com", authMethod: .email))
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "phu@example.com"))
        XCTAssertEqual(rig.coordinator.authMethod, .email)
        XCTAssertNotNil(rig.coordinator.hub)
        // Another account's history goes, as for Google.
        XCTAssertEqual(rig.wiper.wipes, 1)
        let owner = try await rig.vault.machinesOwner()
        XCTAssertEqual(owner, "u1")
    }

    func testEveryRelayAnswerOfTheTwoCallsHasItsFailure() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.coordinator.launch()
        let requests: [(any Error, SignInError)] = [
            (http(400, "invalid_email"), .invalidEmail),
            (http(400, "disposable_email"), .disposableEmail),
            (http(429, "rate_limited"), .rateLimited),
            (http(503, "email_sign_in_disabled"), .providerUnavailable),
            (http(404, "not_found"), .providerUnavailable),
            (http(502, "email_send_failed"), .emailSendFailed),
            (URLError(.notConnectedToInternet), .network),
        ]
        for (relayError, expected) in requests {
            await rig.relay.setError(relayError, for: .requestEmailCode)
            let error = await signInError { _ = try await rig.coordinator.requestEmailCode(email: "phu@example.com") }
            XCTAssertEqual(error, expected, "\(relayError)")
        }
        let verifies: [(any Error, SignInError)] = [
            (http(401, "invalid_code"), .invalidCode),
            (http(410, "code_expired"), .codeExpired),
            (http(409, "switch_from_signed_in_device"), .switchFromSignedInDevice),
            (http(400, "invalid_device"), .server(code: "invalid_device")),
            (http(429, "rate_limited"), .rateLimited),
            (http(404, "not_found"), .providerUnavailable),
            (URLError(.timedOut), .network),
        ]
        for (relayError, expected) in verifies {
            await rig.relay.setError(relayError, for: .signInWithEmailCode)
            let error = await signInError { try await rig.coordinator.signInWithEmailCode(challengeID: "challenge-1", code: "123456") }
            XCTAssertEqual(error, expected, "\(relayError)")
        }
        let session = try await rig.vault.session()
        XCTAssertNil(session)
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
        XCTAssertNil(rig.coordinator.hub)
    }

    func testAPendingWipeBlocksBothCallsBeforeAnyRelayCall() async {
        let rig = await CoordinatorRig.make(self, extraWipers: [FlakyWiper()])
        rig.pendingDefaults.set(true, forKey: "shellx.localWipePending")
        let requestError = await signInError { _ = try await rig.coordinator.requestEmailCode(email: "phu@example.com") }
        XCTAssertEqual(requestError, .localWipePending)
        let verifyError = await signInError { try await rig.coordinator.signInWithEmailCode(challengeID: "challenge-1", code: "123456") }
        XCTAssertEqual(verifyError, .localWipePending)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
    }

    func testDeleteByCodeMailsTheAccountsAddressThenDeletesAndWipesLikeSignOut() async throws {
        let rig = try await emailSession()
        let challenge = try await rig.coordinator.requestDeleteAccountCode()
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "phu@example.com"))
        try await rig.coordinator.deleteAccount(challengeID: challenge.challengeID, code: "123456")
        let calls = await rig.relay.calls
        XCTAssertEqual(
            calls,
            [
                .requestEmailCode(email: "phu@example.com", locale: "vi"),
                .deleteAccountWithCode(challengeID: "challenge-1", code: "123456", token: "tok-old"),
            ], "no nonce, no unpair, no logout")
        XCTAssertEqual(rig.identity.googleNonces, [])
        for item in SecretItem.allCases { XCTAssertNil(try rig.store.read(item)) }
        XCTAssertEqual(rig.wiper.wipes, 1)
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
        XCTAssertNil(rig.coordinator.authMethod)
        XCTAssertNil(rig.coordinator.hub)
    }

    func testAWrongExpiredOrForeignDeleteCodeKeepsEverything() async throws {
        let cases: [(RelayAPIError, SignInError)] = [
            (http(401, "invalid_code"), .invalidCode), (http(410, "code_expired"), .codeExpired),
            (http(401, "reauth_required"), .reauthRequired),
        ]
        for (relayError, expected) in cases {
            let rig = try await emailSession()
            await rig.relay.setError(relayError, for: .deleteAccountWithCode)
            let before = try XCTUnwrap(rig.coordinator.hub)
            let error = await signInError { try await rig.coordinator.deleteAccount(challengeID: "challenge-1", code: "000000") }
            XCTAssertEqual(error, expected)
            let session = try await rig.vault.session()
            XCTAssertEqual(session?.token, "tok-old")
            XCTAssertTrue(rig.coordinator.hub === before)
        }
    }

    func testDeletionAsksForTheRightKindOfProof() async throws {
        let email = try await emailSession()
        let codeRequired = await signInError { try await email.coordinator.deleteAccount() }
        XCTAssertEqual(codeRequired, .server(code: "code_required"))

        let google = await CoordinatorRig.make(self)
        try await google.vault.setSession(
            StoredSession(userID: "u1", deviceID: "d1", token: "tok-old", email: "g@example.com", authMethod: .google))
        await google.coordinator.launch()
        let notEmail = await signInError { _ = try await google.coordinator.requestDeleteAccountCode() }
        XCTAssertEqual(notEmail, .server(code: "not_email_session"))

        for rig in [email, google] {
            let calls = await rig.relay.calls
            XCTAssertEqual(calls, [])
            XCTAssertEqual(rig.identity.googleNonces, [])
        }
    }

    func testUnauthorizedDuringDeleteByCodeEndsSignedOutNotExpired() async throws {
        let rig = try await emailSession()
        let coordinator = rig.coordinator
        await rig.relay.setHook({ await coordinator.handleUnauthorized() }, for: .deleteAccountWithCode)
        try await rig.coordinator.deleteAccount(challengeID: "challenge-1", code: "123456")
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
    }
}
