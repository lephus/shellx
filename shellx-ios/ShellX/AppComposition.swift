import Foundation
import ShellXAppCore
import UIKit

/// Builds the app's object graph. The only place that knows the Keychain, the relay URL, the
/// device name, the clock and the speech recognizers.
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
        removeMergedChatData(in: historyDirectory, defaults: .standard)
        let history = ConversationStore(directory: historyDirectory)
        let launch = LaunchMark(latency: latency)
        let scopes = SignedInScope.Slot()
        // The hub reports a refused token to the coordinator that made it.
        let owner = CoordinatorReference()
        let coordinator = AppCoordinator(
            vault: vault, relay: relay,
            identity: SystemIdentityProvider(
                googleClientID: bundle.object(forInfoDictionaryKey: "ShellXGoogleClientID") as? String),
            deviceName: deviceName, wipers: [history],
            makeHub: {
                let hub = MachineHub(
                    vault: vault, relay: relay, connector: connector, latency: latency, defaults: .standard,
                    sleep: { try await Task.sleep(for: $0) },
                    onUnauthorized: { await owner.coordinator?.handleUnauthorized() })
                scopes.current = makeScope(
                    hub: hub, history: history, latency: latency, launch: launch,
                    pairing: PairingModel(hub: hub, relay: relay, vault: vault), defaults: .standard,
                    voice: VoiceService.system(latency: latency, defaults: .standard, hub: hub))
                return hub
            })
        owner.coordinator = coordinator
        #if DEBUG
        let updatePrompt: UpdatePrompt? = nil
        #else
        let updatePrompt = makeUpdatePrompt(bundleID: bundle.bundleIdentifier, version: version)
        #endif
        // Debug builds (com.shellx.dev) get sandbox APNs tokens, App Store builds production ones.
        let push = PushRegistration(
            relay: relay, vault: vault, topic: bundle.bundleIdentifier ?? "com.shellx.prod",
            environment: debugBuild ? .sandbox : .production)
        return AppGraph(
            coordinator: coordinator, scopes: scopes, launch: launch, updatePrompt: updatePrompt, push: push)
    }

    /// The App Store popup: asks the store of the phone's region about this app. Nil without a bundle id.
    private static func makeUpdatePrompt(bundleID: String?, version: String) -> UpdatePrompt? {
        guard let bundleID else { return nil }
        let url = AppStoreRelease.lookupURL(bundleID: bundleID, country: Locale.current.region?.identifier.lowercased())
        return UpdatePrompt(installedVersion: version) {
            // The store's answer changes when a release goes live: never a cached one.
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    /// One sign-in's scope over `hub`; each agent's chat copy lives in `history`, and the ended sessions
    /// the user takes off the Ended page and the gone ones removed from this phone are kept in `defaults`.
    /// `voice` nil shows no mic.
    static func makeScope(
        hub: MachineHub, history: ConversationStore, latency: LatencyLog, launch: LaunchMark, pairing: PairingModel,
        defaults: UserDefaults = .standard, voice: VoiceService? = nil
    ) -> SignedInScope {
        SignedInScope(
            hub: hub,
            decisions: DecisionCenter(sender: hub, latency: latency, sleep: { try await Task.sleep(for: $0) }),
            pairing: pairing, history: history, launch: launch,
            endedDismissals: EndedDismissalStore(defaults: defaults),
            goneRemovals: GoneRemovalStore(defaults: defaults), voice: voice)
    }

    /// The `UserDefaults` flag that says the merged chat's files are gone.
    static let mergedChatRemovedKey = "shellx.mergedChatRemoved"

    /// Deletes what the merged "ShellX" chat kept in `directory` (the conversation, `home.json`, and the
    /// last seen session states, `last-sessions.json`). The first launch of a version without that chat
    /// does it; `defaults` remembers that it did, so later launches touch nothing. The chat copies of
    /// single agents (`threads/`) stay. A file that cannot be deleted leaves the flag off: the next
    /// launch tries again.
    static func removeMergedChatData(in directory: URL, defaults: UserDefaults, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: mergedChatRemovedKey) else { return }
        for name in ["home.json", "last-sessions.json"] {
            let url = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                return
            }
        }
        defaults.set(true, forKey: mergedChatRemovedKey)
    }
}

@MainActor
private final class CoordinatorReference {
    weak var coordinator: AppCoordinator?
}
