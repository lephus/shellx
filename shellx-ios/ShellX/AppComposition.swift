import Foundation
import ShellXAppCore
import UIKit
#if DEBUG
import ShellXAppTestSupport
#endif

/// Builds the app's object graph. The only place that knows the Keychain, the relay URL and the
/// device name.
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
        // The base URL is https (production) or a validated override, so this cannot fail.
        guard let relay = try? RelayClientFactory.make(apiBase: endpoints.apiBase, appVersion: version) else {
            preconditionFailure("the relay URL must be https")
        }
        return AppCoordinator(
            vault: AccountVault(store: store), relay: relay, deviceName: UIDevice.current.name, wipers: [])
    }
}

#if DEBUG
extension AppCoordinator {
    /// A coordinator over memory and a fake relay, for previews and render tests (Debug only).
    @MainActor
    static func preview() -> AppCoordinator {
        AppCoordinator(
            vault: AccountVault(store: InMemorySecretStore()), relay: FakeRelayAccount(), deviceName: "iPhone",
            wipers: [])
    }
}
#endif
