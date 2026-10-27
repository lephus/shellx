import Foundation
import ShellXAppCore
import UIKit
#if DEBUG
import ShellXAppTestSupport
#endif

/// What the app's screens are built from: the coordinator, and how to make the pairing model and
/// the decision center for the signed-in account's hub.
@MainActor
struct AppGraph {
    let coordinator: AppCoordinator
    let makePairing: @MainActor (MachineHub) -> PairingModel
    let makeDecisions: @MainActor (MachineHub) -> DecisionCenter
    /// Runs once before `coordinator.launch()`; the Debug demo seeds its fake account here.
    var prepare: @MainActor () async -> Void = {}
}

/// Builds the app's object graph. The only place that knows the Keychain, the relay URL, the
/// device name and the clock.
@MainActor
enum AppComposition {
    static func make() -> AppGraph {
        #if DEBUG
        // SHELLX_DEMO=1 (dev.sh sim --demo): an in-process fake Mac, no relay, no Keychain.
        if ProcessInfo.processInfo.environment["SHELLX_DEMO"] == "1" { return DemoComposition.make() }
        let debugBuild = true
        #else
        let debugBuild = false
        #endif
        let bundle = Bundle.main
        let endpoints = ShellXEndpoints(debugBuild: debugBuild, environment: ProcessInfo.processInfo.environment)
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let store = KeychainSecretStore(
            service: bundle.bundleIdentifier ?? "com.shellx.prod",
            accessGroup: bundle.object(forInfoDictionaryKey: "ShellXKeychainGroup") as? String)
        let vault = AccountVault(store: store)
        let deviceName = UIDevice.current.name
        // The base URL is https (production) or a validated override, so this cannot fail.
        guard let relay = try? RelayClientFactory.make(apiBase: endpoints.apiBase, appVersion: version),
            let connector = try? RelayClientFactory.makeConnector(
                apiBase: endpoints.apiBase, appVersion: version, vault: vault, deviceName: deviceName)
        else {
            preconditionFailure("the relay URL must be https")
        }
        let latency = LatencyLog()
        // The hub reports a refused token to the coordinator that made it.
        let owner = CoordinatorReference()
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: deviceName, wipers: [],
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay, connector: connector, latency: latency, defaults: .standard,
                    sleep: { try await Task.sleep(for: $0) },
                    onUnauthorized: { await owner.coordinator?.handleUnauthorized() })
            })
        owner.coordinator = coordinator
        return AppGraph(
            coordinator: coordinator, makePairing: { PairingModel(hub: $0, relay: relay, vault: vault) },
            makeDecisions: { DecisionCenter(sender: $0, latency: latency, sleep: { try await Task.sleep(for: $0) }) })
    }
}

@MainActor
private final class CoordinatorReference {
    weak var coordinator: AppCoordinator?
}

#if DEBUG
extension AppCoordinator {
    /// A coordinator over memory and a fake relay, for previews and render tests (Debug only).
    @MainActor
    static func preview() -> AppCoordinator {
        AppGraph.preview().coordinator
    }
}

extension AppGraph {
    /// A graph over memory and a fake relay, for previews and render tests (Debug only).
    static func preview() -> AppGraph {
        let vault = AccountVault(store: InMemorySecretStore())
        let relay = FakeRelayAccount()
        let latency = LatencyLog()
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: "iPhone", wipers: [],
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay, connector: FakeMacFleet([], phoneKey: { try await vault.phoneKey() }),
                    latency: latency, defaults: .standard, sleep: { try await Task.sleep(for: $0) },
                    onUnauthorized: {})
            })
        return AppGraph(
            coordinator: coordinator, makePairing: { PairingModel(hub: $0, relay: relay, vault: vault) },
            makeDecisions: { DecisionCenter(sender: $0, latency: latency, sleep: { try await Task.sleep(for: $0) }) })
    }
}
#endif
