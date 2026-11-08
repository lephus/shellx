// AppCoordinatorSignInTests.swift
import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest
@testable import ShellXAppCore

@MainActor
final class AppCoordinatorSignInTests: XCTestCase {
    private let google = AccountSignIn(session: AccountSession(userID: "u1", deviceID: "d1", token: "tok-g"), email: "g@example.com")
    private let owner = AccountSignIn(session: AccountSession(userID: "owner", deviceID: "d9", token: "tok-a"), email: "owner@example.com")

    func testGoogleSignInSendsTheNonceTheTokenAndThePhoneKey() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setGoogleSignIn(.success(google))
        await rig.coordinator.launch()
        try await rig.coordinator.signInWithGoogle()
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce, .signInWithGoogle(idToken: "google-id-token", nonce: "nonce-1", deviceName: "Phu's iPhone", clientKey: key)])
        XCTAssertEqual(rig.identity.googleNonces, ["nonce-1"])
        let session = try await rig.vault.session()
        XCTAssertEqual(session, StoredSession(userID: "u1", deviceID: "d1", token: "tok-g", email: "g@example.com", authMethod: .google))
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "g@example.com"))
        XCTAssertEqual(rig.coordinator.authMethod, .google)
        XCTAssertNotNil(rig.coordinator.hub)
    }

    func testGoogleSignInCancelledChangesNothing() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.coordinator.launch()
        rig.identity.googleResult = .failure(IdentityProviderError.cancelled)
        let error = await signInError { try await rig.coordinator.signInWithGoogle() }
        XCTAssertEqual(error, .cancelled)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce])
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
        XCTAssertNil(rig.coordinator.hub)
        rig.identity.googleResult = .success("google-id-token")
        try await rig.coordinator.signInWithGoogle()
        XCTAssertEqual(rig.coordinator.authMethod, .google, "the next tap works")
    }

    func testGoogleSignInErrorsMap() async {
        let cases: [(any Error, SignInError)] = [
            (RelayAPIError.http(status: 409, code: "switch_from_signed_in_device"), .switchFromSignedInDevice),
            (RelayAPIError.http(status: 401, code: "invalid_credentials"), .invalidCredentials),
            (RelayAPIError.http(status: 429, code: "rate_limited"), .rateLimited),
        ]
        for (relayError, expected) in cases {
            let rig = await CoordinatorRig.make(self)
            await rig.relay.setGoogleSignIn(.failure(relayError))
            let error = await signInError { try await rig.coordinator.signInWithGoogle() }
            XCTAssertEqual(error, expected)
        }
        let rig = await CoordinatorRig.make(self)
        rig.identity.googleResult = .failure(IdentityProviderError.notConfigured)
        let error = await signInError { try await rig.coordinator.signInWithGoogle() }
        XCTAssertEqual(error, .providerUnavailable)
    }

    func testGoogleSignInAsAnotherAccountWipesTheOldHistory() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setGoogleSignIn(.success(google))
        try await rig.vault.setMachines([PairedMachine(machineID: "m0", name: "Old", linkSlot: "s0", hostKey: Data(repeating: 1, count: 32))], owner: "someone-else")
        try await rig.coordinator.signInWithGoogle()
        XCTAssertEqual(rig.wiper.wipes, 1)
        let machines = try await rig.vault.machines()
        let owner = try await rig.vault.machinesOwner()
        XCTAssertEqual(machines, [])
        XCTAssertEqual(owner, "u1")
    }

    func testPendingWipeBlocksGoogleSignInBeforeAnyRelayCall() async {
        let flaky = FlakyWiper()
        let rig = await CoordinatorRig.make(self, extraWipers: [flaky])
        rig.pendingDefaults.set(true, forKey: "shellx.localWipePending")
        let error = await signInError { try await rig.coordinator.signInWithGoogle() }
        XCTAssertEqual(error, .localWipePending)
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
    }

    func testAppleSignInHashesTheNonceForAppleAndSendsItRaw() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setAppleSignIn(.success(.signedIn(owner)))
        try await rig.coordinator.signInWithApple()
        XCTAssertEqual(rig.identity.appleRequestNonces, [AuthCrypto.sha256Hex("nonce-1")])
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.nonce, .signInWithApple(
            identityToken: "apple-id-token", authorizationCode: "apple-code", nonce: "nonce-1", deviceName: "Phu's iPhone", clientKey: key)])
        XCTAssertEqual(rig.coordinator.authMethod, .apple)
        let session = try await rig.vault.session()
        XCTAssertEqual(session?.authMethod, .apple)
    }

    func testAppleWithoutAccountLinksThroughTheMac() async throws {
        let mac = FakeMac(name: "Studio")
        let rig = await CoordinatorRig.make(self, macs: [mac])
        await rig.relay.setAppleSignIn(.success(.linkRequired(linkToken: "link-1", expiresIn: 600)))
        await rig.relay.setAppleLinkSignIn(owner)
        await rig.coordinator.launch()
        try await rig.coordinator.signInWithApple()
        XCTAssertEqual(rig.coordinator.phase, .linkingApple)
        let stored = try await rig.vault.session()
        XCTAssertNil(stored, "nothing is stored before the Mac allows it")
        let link = try XCTUnwrap(rig.coordinator.appleLink)
        link.begin(uri: await mac.pairingCode())
        await link.confirm()
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "owner@example.com"))
        XCTAssertEqual(rig.coordinator.authMethod, .apple)
        XCTAssertNil(rig.coordinator.appleLink)
        let machines = try await rig.vault.machines()
        let machineOwner = try await rig.vault.machinesOwner()
        XCTAssertEqual(machines, [mac.machine])
        XCTAssertEqual(machineOwner, "owner")
        let online = await eventually { rig.coordinator.hub?.machines.first?.state == .online }
        XCTAssertTrue(online)
    }

    func testLinkKeepsThisAccountsOtherMacsAndWipesAnotherAccountsHistory() async throws {
        let mac = FakeMac(name: "Studio")
        let other = PairedMachine(machineID: "m0", name: "Old", linkSlot: "s0", hostKey: Data(repeating: 1, count: 32))
        for (previousOwner, expected, wipes) in [("owner", [other, mac.machine], 0), ("someone-else", [mac.machine], 1)] {
            let rig = await CoordinatorRig.make(self, macs: [mac])
            try await rig.vault.setMachines([other], owner: previousOwner)
            await rig.relay.setAppleSignIn(.success(.linkRequired(linkToken: "link-1", expiresIn: 600)))
            await rig.relay.setAppleLinkSignIn(owner)
            try await rig.coordinator.signInWithApple()
            let link = try XCTUnwrap(rig.coordinator.appleLink)
            link.begin(uri: await mac.pairingCode())
            await link.confirm()
            let machines = try await rig.vault.machines()
            XCTAssertEqual(machines, expected, previousOwner)
            XCTAssertEqual(rig.wiper.wipes, wipes, previousOwner)
        }
    }

    func testEndedLinksReturnToSignInWithANoticeThatTheNextSignInClears() async throws {
        let cases: [(any Error, SignInNotice)] = [
            (PhonePairingError.denied, .appleLinkDenied), (RelayAPIError.http(status: 401, code: "invalid_credentials"), .appleLinkExpired),
        ]
        for (error, notice) in cases {
            let rig = await CoordinatorRig.make(self)
            await rig.relay.setAppleSignIn(.success(.linkRequired(linkToken: "link-1", expiresIn: 600)))
            await rig.relay.setError(error, for: .linkApple)
            try await rig.coordinator.signInWithApple()
            let link = try XCTUnwrap(rig.coordinator.appleLink)
            link.begin(uri: PairingOffer.make(machineID: "m1", linkSlot: "s1", hostKey: Data(repeating: 4, count: 32), machineName: "Studio").uri)
            await link.confirm()
            XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
            XCTAssertEqual(rig.coordinator.signInNotice, notice)
            XCTAssertNil(rig.coordinator.appleLink)
            try await rig.coordinator.signInWithGoogle()
            XCTAssertNil(rig.coordinator.signInNotice)
        }
    }

    func testClosingTheLinkReturnsToSignInQuietly() async throws {
        let rig = await CoordinatorRig.make(self)
        await rig.relay.setAppleSignIn(.success(.linkRequired(linkToken: "link-1", expiresIn: 600)))
        try await rig.coordinator.signInWithApple()
        try XCTUnwrap(rig.coordinator.appleLink).close()
        let back = await eventually { rig.coordinator.phase == .signedOut(expired: false) }
        XCTAssertTrue(back)
        XCTAssertNil(rig.coordinator.signInNotice)
        XCTAssertNil(rig.coordinator.appleLink)
    }
}
