import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import XCTest
@testable import ShellXAppCore

/// A signed-out AppCoordinator over memory, a FakeRelayAccount and a FakeIdentityProvider. Its hubs reach `macs`
/// and report a refused token to the coordinator.
@MainActor
struct CoordinatorRig {
    let store: InMemorySecretStore
    let vault: AccountVault
    let relay: FakeRelayAccount
    let identity: FakeIdentityProvider
    let wiper: CountingWiper
    let pendingDefaults: UserDefaults
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
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, identity: identity, deviceName: "Phu's iPhone", wipers: extraWipers + [wiper],
            pendingWipeDefaults: pendingDefaults,
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
            coordinator: coordinator)
    }
}

/// The error a sign-in, a switch or a deletion threw; nil when it succeeded.
@MainActor
func signInError(_ body: () async throws(SignInError) -> Void) async -> SignInError? {
    do { try await body(); return nil } catch { return error }
}
