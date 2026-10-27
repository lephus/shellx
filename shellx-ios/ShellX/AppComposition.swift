import Foundation
import ShellXAppCore
import UIKit
#if DEBUG
import ShellXAppTestSupport
#endif

/// What the app's screens are built from: the coordinator, and the signed-in account's scope (its
/// hub, decision center, home model and pairing model), made with each hub the coordinator makes.
@MainActor
struct AppGraph {
    let coordinator: AppCoordinator
    let scopes: SignedInScope.Slot
    /// Measures `launchToHome`.
    let launch: LaunchMark
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
        // History lives in Application Support/ShellX and is wiped on sign-out.
        let historyDirectory = URL.applicationSupportDirectory.appendingPathComponent("ShellX", isDirectory: true)
        let history = ConversationStore(directory: historyDirectory)
        let launch = LaunchMark(latency: latency)
        let scopes = SignedInScope.Slot()
        // The hub reports a refused token to the coordinator that made it.
        let owner = CoordinatorReference()
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: deviceName, wipers: [history],
            makeHub: {
                let hub = MachineHub(
                    vault: vault, relay: relay, connector: connector, latency: latency, defaults: .standard,
                    sleep: { try await Task.sleep(for: $0) },
                    onUnauthorized: { await owner.coordinator?.handleUnauthorized() })
                scopes.current = makeScope(
                    hub: hub, history: history, latency: latency, launch: launch,
                    pairing: PairingModel(hub: hub, relay: relay, vault: vault))
                return hub
            })
        owner.coordinator = coordinator
        return AppGraph(coordinator: coordinator, scopes: scopes, launch: launch)
    }

    /// One sign-in's scope over `hub`; the home's history lives in `history`.
    static func makeScope(
        hub: MachineHub, history: ConversationStore, latency: LatencyLog, launch: LaunchMark, pairing: PairingModel
    ) -> SignedInScope {
        SignedInScope(
            hub: hub,
            decisions: DecisionCenter(sender: hub, latency: latency, sleep: { try await Task.sleep(for: $0) }),
            home: HomeModel(hub: hub, store: history, now: { Date() }),
            pairing: pairing, launch: launch)
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
        let launch = LaunchMark(latency: latency)
        let scopes = SignedInScope.Slot()
        let history = ConversationStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("ShellXPreview", isDirectory: true))
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: "iPhone", wipers: [history],
            makeHub: {
                let hub = MachineHub(
                    vault: vault, relay: relay, connector: FakeMacFleet([], phoneKey: { try await vault.phoneKey() }),
                    latency: latency, defaults: .standard, sleep: { try await Task.sleep(for: $0) },
                    onUnauthorized: {})
                scopes.current = AppComposition.makeScope(
                    hub: hub, history: history, latency: latency, launch: launch,
                    pairing: PairingModel(hub: hub, relay: relay, vault: vault))
                return hub
            })
        return AppGraph(coordinator: coordinator, scopes: scopes, launch: launch)
    }
}
#endif
