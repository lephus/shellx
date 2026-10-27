import Foundation
import ShellXAppCore
import UIKit
#if DEBUG
import ShellXAppTestSupport
#endif

/// Builds the app's object graph. The only place that knows the Keychain, the relay URL, the
/// device name and the clock.
@MainActor
enum AppComposition {
    static func makeCoordinator() -> AppCoordinator {
        let bundle = Bundle.main
        #if DEBUG
        let debugBuild = true
        #else
        let debugBuild = false
        #endif
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
        return coordinator
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
        let vault = AccountVault(store: InMemorySecretStore())
        let relay = FakeRelayAccount()
        return AppCoordinator(
            vault: vault, relay: relay, deviceName: "iPhone", wipers: [],
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay, connector: FakeMacFleet([], phoneKey: { try await vault.phoneKey() }),
                    latency: LatencyLog(), defaults: .standard, sleep: { try await Task.sleep(for: $0) },
                    onUnauthorized: {})
            })
    }
}
#endif
