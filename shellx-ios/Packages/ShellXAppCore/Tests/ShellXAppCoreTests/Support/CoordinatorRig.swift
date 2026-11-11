import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import XCTest
@testable import ShellXAppCore

/// A signed-out AppCoordinator over memory, a FakeRelayAccount and a FakeIdentityProvider. Its hubs reach `macs`
/// and report a refused token to the coordinator. The app shows Vietnamese (`emailLocale` "vi"), and the Resend lock
/// of the email sign-in runs on `clock`.
@MainActor
struct CoordinatorRig {
    let store: InMemorySecretStore
    let vault: AccountVault
    let relay: FakeRelayAccount
    let identity: FakeIdentityProvider
    let wiper: CountingWiper
    let pendingDefaults: UserDefaults
    let clock: ManualClock
    let coordinator: AppCoordinator

    static func make(
        _ test: XCTestCase, macs: [FakeMac] = [], extraWipers: [any LocalDataWiping] = [],
        store: InMemorySecretStore = InMemorySecretStore(),
        pendingDefaults: UserDefaults = UserDefaults(suiteName: "CoordinatorRig-pending-\(UUID().uuidString)")!
    ) async -> CoordinatorRig {
        let vault = AccountVault(store: store)
        let relay = FakeRelayAccount()
        let identity = FakeIdentityProvider()
        let wiper = CountingWiper()
        let defaults = UserDefaults(suiteName: "CoordinatorRig-\(UUID().uuidString)")!
        let box = CoordinatorBox()
        let clock = ManualClock()
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, identity: identity, deviceName: "Phu's iPhone", wipers: extraWipers + [wiper],
            pendingWipeDefaults: pendingDefaults, emailLocale: "vi", clock: clock,
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay, connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }),
                    latency: LatencyLog(), defaults: defaults, sleep: instantSleep,
                    onUnauthorized: { await box.coordinator?.handleUnauthorized() })
            })
        box.coordinator = coordinator
        test.addTeardownBlock { await coordinator.hub?.stopAll() }
        return CoordinatorRig(
            store: store, vault: vault, relay: relay, identity: identity, wiper: wiper, pendingDefaults: pendingDefaults,
            clock: clock, coordinator: coordinator)
    }
}

/// The error a sign-in, a switch or a deletion threw; nil when it succeeded.
@MainActor
func signInError(_ body: () async throws -> Void) async -> SignInError? {
    // Swift 6.0 does not infer a typed throw for a closure literal, so the body throws `any Error`.
    do { try await body(); return nil } catch { return error as? SignInError }
}
