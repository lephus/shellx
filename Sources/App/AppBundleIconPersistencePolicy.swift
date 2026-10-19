import Foundation

enum AppBundleIconPersistencePolicy {
    // `ShellXBrand.bundleID` / `"\(ShellXBrand.appName).app"`, spelled out: this file is also
    // compiled into the CmuxDockTilePlugin target, which links no package products.
    // tests/test_shellx_identity.py checks both values against ShellXBrand.
    private static let stableReleaseBundleIdentifier = "pro.shellx.desktop"
    private static let stableReleaseAppBundleName = "ShellX.app"
    static let disablePersistenceArgument = "--cmux-disable-bundle-icon-persistence"
    static let disablePersistenceDefaultsKey = "cmuxDisableBundleIconPersistence"

    static func updateDisableDefault(defaults: UserDefaults, launchArguments: [String]) {
        defaults.set(
            launchArguments.contains(disablePersistenceArgument),
            forKey: disablePersistenceDefaultsKey
        )
    }

    static func shouldPersist(
        bundleIdentifier: String?,
        appBundleLastPathComponent: String?,
        persistenceDisabled: Bool = false
    ) -> Bool {
        guard !persistenceDisabled else {
            return false
        }

        // Channel variants own their identity through build-time bundle metadata.
        // Persisted Finder icons would override that metadata and can leak into
        // packaged artifacts after CI smoke launches the app bundle.
        return bundleIdentifier == stableReleaseBundleIdentifier
            && appBundleLastPathComponent == stableReleaseAppBundleName
    }
}
