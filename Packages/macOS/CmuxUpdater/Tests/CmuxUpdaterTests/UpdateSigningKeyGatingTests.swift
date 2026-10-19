import Foundation
import Testing
@testable import CmuxUpdater

/// ShellX ships without a Sparkle EdDSA key (`SUPublicEDKey` is empty) until its update feed is
/// signed. Sparkle refuses to start with an empty key ("The EdDSA public key is not valid"), so
/// the controller must never start it then: no error at launch, no appcast query, and a manual
/// check reports "No Updates Available" like a DEV build's.
@MainActor
@Suite struct UpdateSigningKeyGatingTests {
    @Test func onlyANonEmptyStringIsAnUpdateSigningKey() {
        #expect(!UpdateController.hasUpdateSigningKey(infoValue: nil))
        #expect(!UpdateController.hasUpdateSigningKey(infoValue: ""))
        #expect(!UpdateController.hasUpdateSigningKey(infoValue: " \n"))
        #expect(!UpdateController.hasUpdateSigningKey(infoValue: 42))
        #expect(UpdateController.hasUpdateSigningKey(infoValue: "avjcgKibf1FTvhIjLBxhd+0HSpsXU4D0IGlVk8cgqRc="))
    }

    @Test func withoutAKeySparkleNeverStartsAndManualChecksFindNothing() throws {
        let (controller, updater, defaults, cleanup) = try makeController(hasUpdateSigningKey: false)
        defer { cleanup() }

        #expect(!controller.startUpdaterIfNeeded())
        #expect(updater.startCallCount == 0)
        #expect(defaults.bool(forKey: UpdateSettings.automaticChecksKey) == false)

        controller.checkForUpdates()
        #expect(updater.startCallCount == 0)
        #expect(updater.checkForUpdatesCallCount == 0)
        guard case .notFound = controller.model.state else {
            Issue.record("a manual check without a signing key should surface .notFound, got \(controller.model.state)")
            return
        }
    }

    @Test func withAKeySparkleStarts() throws {
        let (controller, updater, _, cleanup) = try makeController(hasUpdateSigningKey: true)
        defer { cleanup() }

        #expect(controller.startUpdaterIfNeeded())
        #expect(updater.startCallCount == 1)
    }

    /// The test runner's own bundle has no `SUPublicEDKey`, so a controller that derives the
    /// value from its host bundle treats it as unsigned.
    @Test func derivesTheKeyFromTheHostBundleByDefault() throws {
        let suiteName = "pro.shellx.desktop.updatertests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updater = FakeUpdater()
        let controller = UpdateController(
            log: NoopUpdateLog(),
            hostBundle: .main,
            defaults: defaults,
            isDevLikeBundle: false,
            updaterFactory: { _, _ in updater }
        )
        #expect(!controller.hasUpdateSigningKey)
        #expect(!controller.startUpdaterIfNeeded())
    }

    private func makeController(
        hasUpdateSigningKey: Bool
    ) throws -> (UpdateController, FakeUpdater, UserDefaults, () -> Void) {
        let suiteName = "pro.shellx.desktop.updatertests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let updater = FakeUpdater()
        let controller = UpdateController(
            log: NoopUpdateLog(),
            hostBundle: .main,
            defaults: defaults,
            isDevLikeBundle: false,
            hasUpdateSigningKey: hasUpdateSigningKey,
            updaterFactory: { _, _ in updater }
        )
        return (controller, updater, defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }
}
