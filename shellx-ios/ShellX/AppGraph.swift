import Foundation
import ShellXAppCore
#if DEBUG
import ShellXAppTestSupport
#endif

/// What the app's screens are built from: the coordinator, and the signed-in account's scope (its
/// hub, decision center, pairing model and history), made with each hub the coordinator makes.
@MainActor
struct AppGraph {
    let coordinator: AppCoordinator
    let scopes: SignedInScope.Slot
    /// Measures `launchToHome`.
    let launch: LaunchMark
    /// Runs once before `coordinator.launch()`; the Debug demo seeds its fake account here.
    var prepare: @MainActor () async -> Void = {}
    /// Offers a newer App Store version; nil in Debug builds, which are not on the store.
    var updatePrompt: UpdatePrompt?
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
