import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

final class CountingWiper: LocalDataWiping, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var wipes: Int { lock.lock(); defer { lock.unlock() }; return count }
    func wipe() async { increment() }
    private func increment() { lock.lock(); count += 1; lock.unlock() }
}

/// A wiper that throws while `failing` is set, and counts its attempts.
final class FlakyWiper: LocalDataWiping, @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var isFailing = true
    private var attemptCount = 0
    var attempts: Int { lock.lock(); defer { lock.unlock() }; return attemptCount }
    func setFailing(_ value: Bool) { lock.lock(); isFailing = value; lock.unlock() }
    func wipe() async throws {
        if recordAttempt() { throw Failure() }
    }
    private func recordAttempt() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        attemptCount += 1
        return isFailing
    }
}

@MainActor
final class AppCoordinatorTests: XCTestCase {
    private let account = AccountSession(userID: "u1", deviceID: "d1", token: "tok-1")
    private let mac = PairedMachine(machineID: "m1", name: "Mac", linkSlot: "s1", hostKey: Data(repeating: 1, count: 32))

    private struct Rig {
        var store: InMemorySecretStore
        var vault: AccountVault
        var relay: FakeRelayAccount
        var wiper: CountingWiper
        var coordinator: AppCoordinator
    }

    private func rig(
        store: InMemorySecretStore = InMemorySecretStore(), extraWipers: [any LocalDataWiping] = [],
        pendingDefaults: UserDefaults = UserDefaults(suiteName: "AppCoordinatorTests-pending-\(UUID().uuidString)")!
    ) async -> Rig {
        let vault = AccountVault(store: store)
        let relay = FakeRelayAccount()
        await relay.setLogin(.success(account))
        let wiper = CountingWiper()
        let defaults = UserDefaults(suiteName: "AppCoordinatorTests-\(UUID().uuidString)")!
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: "Phu's iPhone", wipers: extraWipers + [wiper], pendingWipeDefaults: pendingDefaults,
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay, connector: FakeMacFleet([], phoneKey: { try await vault.phoneKey() }),
                    latency: LatencyLog(), defaults: defaults, sleep: { _ in }, onUnauthorized: {})
            })
        addTeardownBlock { await coordinator.hub?.stopAll() }
        return Rig(store: store, vault: vault, relay: relay, wiper: wiper, coordinator: coordinator)
    }

    func testSignedInStartsHubAndSignOutStopsIt() async throws {
        let rig = await rig()
        await rig.coordinator.launch()
        XCTAssertNil(rig.coordinator.hub, "no hub while signed out")

        try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
        let hub = try XCTUnwrap(rig.coordinator.hub)
        try await rig.vault.setMachines([mac], owner: "u1")
        await rig.coordinator.launch()
        XCTAssertTrue(rig.coordinator.hub === hub, "launching again keeps the running hub")

        await rig.coordinator.signOut()
        XCTAssertNil(rig.coordinator.hub)

        // A stored session starts the hub at launch, with the saved Macs; a 401 drops it.
        try await rig.vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "t", email: "a@b.c"))
        try await rig.vault.setMachines([mac], owner: "u1")
        await rig.coordinator.launch()
        XCTAssertEqual(rig.coordinator.hub?.machines.map(\.machine), [mac])
        await rig.coordinator.handleUnauthorized()
        XCTAssertNil(rig.coordinator.hub)
    }

    func testLaunchWithoutSessionIsSignedOut() async {
        let rig = await rig()
        XCTAssertEqual(rig.coordinator.phase, .launching)
        await rig.coordinator.launch()
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
    }

    func testLaunchWithSessionIsSignedIn() async throws {
        let rig = await rig()
        try await rig.vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "t", email: "a@b.c"))
        await rig.coordinator.launch()
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "a@b.c"))
    }

    func testUnavailableKeychainDoesNotSignOut() async throws {
        let store = InMemorySecretStore()
        let rig = await rig(store: store)
        try await rig.vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "t", email: "a@b.c"))
        store.failReads = .unavailable(status: -25308)
        await rig.coordinator.launch()
        XCTAssertEqual(rig.coordinator.phase, .launching)

        store.failReads = nil
        await rig.coordinator.protectedDataBecameAvailable()
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "a@b.c"))
    }

    func testSignInSendsStoredPhoneKey() async throws {
        let rig = await rig()
        await rig.coordinator.launch()
        try await rig.coordinator.signIn(email: "a@b.c", password: "pw-secret")
        let stored = try await rig.vault.phoneKey()
        let calls = await rig.relay.calls
        guard case let .login(email, deviceName, clientKey)? = calls.first else { return XCTFail("\(calls)") }
        XCTAssertEqual(email, "a@b.c")
        XCTAssertEqual(deviceName, "Phu's iPhone")
        XCTAssertEqual(clientKey, stored.publicKey)
        XCTAssertEqual(rig.coordinator.phase, .signedIn(email: "a@b.c"))
        let session = try await rig.vault.session()
        XCTAssertEqual(session, StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))

        // A second sign-in reuses the same key.
        try await rig.coordinator.signIn(email: "a@b.c", password: "pw-secret")
        let keys = await rig.relay.calls.compactMap { call -> Data? in
            if case let .login(_, _, key) = call { return key } else { return nil }
        }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1])
    }

    func testSignInMapsInvalidCredentialsAndRateLimit() async throws {
        let rig = await rig()
        let cases: [(Error, SignInError)] = [
            (RelayAPIError.http(status: 401, code: "invalid_credentials"), .invalidCredentials),
            (RelayAPIError.http(status: 429, code: "rate_limited"), .rateLimited),
            (URLError(.notConnectedToInternet), .network),
            (RelayAPIError.http(status: 500, code: "internal"), .server(code: "internal")),
            (RelayAPIError.badResponse, .server(code: "bad_response")),
        ]
        for (thrown, expected) in cases {
            await rig.relay.setLogin(.failure(thrown))
            do {
                try await rig.coordinator.signIn(email: "a@b.c", password: "x")
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error, expected)
            }
        }
        let session = try await rig.vault.session()
        XCTAssertNil(session)
    }

    func testSignOutUnpairsLogsOutAndWipes() async throws {
        let rig = await rig()
        await rig.relay.setGrants([
            PairedMachineListing(grantID: "g1", machineID: "m1", name: "A", platform: "macos", online: true, linkSlot: "s", fingerprint: "f"),
            PairedMachineListing(grantID: "g2", machineID: "m2", name: "B", platform: "macos", online: false, linkSlot: "s", fingerprint: "f"),
        ])
        try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
        try await rig.vault.setMachines([mac], owner: "u1")
        await rig.relay.resetCalls()

        await rig.coordinator.signOut()

        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [
            .machines(token: "tok-1"), .unpair(grantID: "g1", token: "tok-1"),
            .unpair(grantID: "g2", token: "tok-1"), .logout(token: "tok-1"),
        ])
        for item in SecretItem.allCases { XCTAssertNil(try rig.store.read(item)) }
        XCTAssertEqual(rig.wiper.wipes, 1)
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
    }

    func testSignOutWipesEvenWhenRelayUnreachable() async throws {
        let rig = await rig()
        try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
        await rig.relay.setError(URLError(.notConnectedToInternet), for: .machines)
        await rig.relay.setError(URLError(.notConnectedToInternet), for: .unpair)
        await rig.relay.setError(URLError(.notConnectedToInternet), for: .logout)

        await rig.coordinator.signOut()

        for item in SecretItem.allCases { XCTAssertNil(try rig.store.read(item)) }
        XCTAssertEqual(rig.wiper.wipes, 1)
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false))
    }

    func testExpiredTokenKeepsMachinesForSameAccount() async throws {
        let rig = await rig()
        try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
        try await rig.vault.setMachines([mac], owner: "u1")
        let key = try await rig.vault.phoneKey()

        await rig.coordinator.handleUnauthorized()
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: true))
        let session = try await rig.vault.session()
        XCTAssertNil(session)
        XCTAssertEqual(rig.wiper.wipes, 0)

        try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
        let machines = try await rig.vault.machines()
        let keyAfter = try await rig.vault.phoneKey()
        XCTAssertEqual(machines, [mac])
        XCTAssertEqual(keyAfter.publicKey, key.publicKey)
        XCTAssertEqual(rig.wiper.wipes, 0)
    }

    func testSignInAsOtherAccountDropsMachines() async throws {
        let rig = await rig()
        try await rig.vault.setMachines([mac], owner: "someone-else")
        try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
        let machines = try await rig.vault.machines()
        let owner = try await rig.vault.machinesOwner()
        XCTAssertEqual(machines, [])
        XCTAssertEqual(owner, "u1")
        XCTAssertEqual(rig.wiper.wipes, 1)
    }

    func testFailedWipeOnOtherAccountSignInKeepsOwnerAndRetriesWipe() async throws {
        let flaky = FlakyWiper()
        let rig = await rig(extraWipers: [flaky])
        try await rig.vault.setMachines([mac], owner: "someone-else")

        do {
            try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
            XCTFail("sign-in must fail while the previous account's data is still on the phone")
        } catch {
            XCTAssertEqual(error, .localWipePending)
        }
        // Every wiper ran although the first threw; the owner is still the previous account.
        XCTAssertEqual(flaky.attempts, 1)
        XCTAssertEqual(rig.wiper.wipes, 1)
        let ownerAfterFailure = try await rig.vault.machinesOwner()
        let session = try await rig.vault.session()
        XCTAssertEqual(ownerAfterFailure, "someone-else")
        XCTAssertNil(session)

        flaky.setFailing(false)
        try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
        XCTAssertEqual(flaky.attempts, 2)
        XCTAssertEqual(rig.wiper.wipes, 2)
        let owner = try await rig.vault.machinesOwner()
        XCTAssertEqual(owner, "u1")
    }

    func testSignOutWithFailingWiperRetriesAtLaunchAndBlocksSignInUntilWiped() async throws {
        let flaky = FlakyWiper()
        let pending = UserDefaults(suiteName: "AppCoordinatorTests-pending-\(UUID().uuidString)")!
        let rig = await rig(extraWipers: [flaky], pendingDefaults: pending)
        flaky.setFailing(false)
        try await rig.coordinator.signIn(email: "a@b.c", password: "pw")
        flaky.setFailing(true)

        await rig.coordinator.signOut()
        XCTAssertEqual(rig.coordinator.phase, .signedOut(expired: false), "sign-out still completes")
        XCTAssertEqual(rig.wiper.wipes, 1, "the other wiper ran although the first threw")
        // The vault is empty (no owner), so only the marker can force the retry.
        let owner = try await rig.vault.machinesOwner()
        XCTAssertNil(owner)

        // A new launch retries and the wipe still fails: the marker stays and sign-in is refused.
        let relaunched = AppCoordinator(
            vault: rig.vault, relay: rig.relay, deviceName: "iPhone", wipers: [flaky, rig.wiper],
            pendingWipeDefaults: pending,
            makeHub: { preconditionFailure("no hub expected") })
        await relaunched.launch()
        XCTAssertEqual(flaky.attempts, 2)  // sign-out, then launch
        do {
            try await relaunched.signIn(email: "x@y.z", password: "pw")
            XCTFail("sign-in must be blocked")
        } catch {
            XCTAssertEqual(error, .localWipePending)
        }
        XCTAssertEqual(relaunched.phase, .signedOut(expired: false))

        // Once the wipe works, the next sign-in clears the marker and goes through.
        flaky.setFailing(false)
        await relaunched.launch()
        let attemptsAfterLaunch = flaky.attempts
        XCTAssertEqual(attemptsAfterLaunch, 4, "the blocked sign-in and this launch each retried once")
        XCTAssertFalse(pending.bool(forKey: "shellx.localWipePending"))
        XCTAssertEqual(relaunched.phase, .signedOut(expired: false))
    }
}
