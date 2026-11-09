import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import XCTest
@testable import ShellXAppCore

@MainActor
final class AccountChangeTests: XCTestCase {
    private let googleSession = AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-google"), email: "g@example.com")

    private func signedIn(_ method: AccountAuthMethod, macs: [FakeMac] = []) async throws -> CoordinatorRig {
        let rig = await CoordinatorRig.make(self, macs: macs)
        try await rig.vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-old", email: "old@example.com", authMethod: method))
        try await rig.vault.setMachines(macs.map { $0.machine }, owner: "u1")
        await rig.relay.setLinkGoogle(.success(googleSession))
        await rig.coordinator.launch()
        return rig
    }

    func testSwitchToGoogleStoresTheGoogleSessionAndRestartsTheHub() async throws {
        let mac = FakeMac(name: "Studio")
        let rig = try await signedIn(.password, macs: [mac])
        let before = try XCTUnwrap(rig.coordinator.hub)
        try await rig.coordinator.switchToGoogle()
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce, .linkGoogle(idToken: "google-id-token", nonce: "nonce-1", token: "tok-old")])
        let session = try await rig.vault.session()
        XCTAssertEqual(session, StoredSession(userID: "u1", deviceID: "d1", token: "tok-google", email: "g@example.com", authMethod: .google))
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "g@example.com"))
        XCTAssertEqual(rig.coordinator.authMethod, .google)
        let after = try XCTUnwrap(rig.coordinator.hub)
        XCTAssertFalse(after === before)
        XCTAssertEqual(after.machines.map(\.id), [mac.machine.machineID], "the Macs stay")
    }

    func testSwitchIsOnlyForPasswordSessions() async throws {
        let rig = try await signedIn(.google)
        try await rig.coordinator.switchToGoogle()
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
    }

    func testFailedSwitchKeepsThePasswordSessionAndTheHub() async throws {
        for (code, expected) in [("email_in_use", SignInError.emailInUse), ("identity_in_use", .identityInUse)] {
            let rig = try await signedIn(.password)
            await rig.relay.setLinkGoogle(.failure(RelayAPIError.http(status: 409, code: code)))
            let before = try XCTUnwrap(rig.coordinator.hub)
            let error = await signInError { try await rig.coordinator.switchToGoogle() }
            XCTAssertEqual(error, expected)
            let session = try await rig.vault.session()
            XCTAssertEqual(session?.token, "tok-old")
            XCTAssertEqual(session?.authMethod, .password)
            XCTAssertTrue(rig.coordinator.hub === before)
        }
    }

    func testSwitchWithARefusedTokenSignsOutAsExpired() async throws {
        let mac = FakeMac(name: "Studio")
        let rig = try await signedIn(.password, macs: [mac])
        await rig.relay.setLinkGoogle(.failure(RelayAPIError.http(status: 401, code: "unauthorized")))
        _ = await signInError { try await rig.coordinator.switchToGoogle() }
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: true))
        let machines = try await rig.vault.machines()
        XCTAssertEqual(machines, [mac.machine])
    }

    func testUnauthorizedDuringSwitchIsIgnoredAndTheNewSessionStays() async throws {
        let rig = try await signedIn(.password)
        let coordinator = rig.coordinator
        await rig.relay.setHook({ await coordinator.handleUnauthorized() }, for: .linkGoogle)
        try await rig.coordinator.switchToGoogle()
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "g@example.com"))
        let session = try await rig.vault.session()
        XCTAssertEqual(session?.token, "tok-google")
    }

    func testDeleteGoogleAccountReauthenticatesDeletesAndWipesLikeSignOut() async throws {
        let rig = try await signedIn(.google)
        rig.identity.googleResult = .success("google-fresh")
        try await rig.coordinator.deleteAccount()
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce, .deleteAccount(idToken: "google-fresh", nonce: "nonce-1", token: "tok-old")], "no unpair, no logout")
        for item in SecretItem.allCases { XCTAssertNil(try rig.store.read(item)) }
        XCTAssertEqual(rig.wiper.wipes, 1)
        XCTAssertFalse(rig.pendingDefaults.bool(forKey: "shellx.localWipePending"))
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
        XCTAssertNil(rig.coordinator.authMethod)
        XCTAssertNil(rig.coordinator.hub)
    }

    func testDeleteAppleAccountSignsInWithAppleUsingTheHashedNonce() async throws {
        let rig = try await signedIn(.apple)
        try await rig.coordinator.deleteAccount()
        XCTAssertEqual(rig.identity.appleRequestNonces, [AuthCrypto.sha256Hex("nonce-1")])
        let calls = await rig.relay.calls
        XCTAssertEqual(calls.last, .deleteAccount(idToken: "apple-id-token", nonce: "nonce-1", token: "tok-old"))
    }

    func testDeletePasswordSessionAsksToSwitchFirst() async throws {
        let rig = try await signedIn(.password)
        let error = await signInError { try await rig.coordinator.deleteAccount() }
        XCTAssertEqual(error, .switchToGoogleFirst)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
        XCTAssertEqual(rig.identity.googleNonces, [])
    }

    func testCancelledOrRefusedDeleteKeepsEverything() async throws {
        let cancelled = try await signedIn(.google)
        cancelled.identity.googleResult = .failure(IdentityProviderError.cancelled)
        let cancelError = await signInError { try await cancelled.coordinator.deleteAccount() }
        XCTAssertEqual(cancelError, .cancelled)
        let cancelCalls = await cancelled.relay.calls
        XCTAssertEqual(cancelCalls, [.nonce])

        let refused = try await signedIn(.google)
        await refused.relay.setError(RelayAPIError.http(status: 401, code: "reauth_required"), for: .deleteAccount)
        let before = try XCTUnwrap(refused.coordinator.hub)
        let refusedError = await signInError { try await refused.coordinator.deleteAccount() }
        XCTAssertEqual(refusedError, .reauthRequired)
        let session = try await refused.vault.session()
        XCTAssertEqual(session?.token, "tok-old")
        XCTAssertTrue(refused.coordinator.hub === before)
    }

    func testUnauthorizedDuringDeleteEndsSignedOutNotExpired() async throws {
        let rig = try await signedIn(.google)
        let coordinator = rig.coordinator
        await rig.relay.setHook({ await coordinator.handleUnauthorized() }, for: .deleteAccount)
        try await rig.coordinator.deleteAccount()
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
    }
}
