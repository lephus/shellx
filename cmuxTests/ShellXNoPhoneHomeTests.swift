import CmuxFeedback
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV

/// ShellX never phones home: no telemetry, no remote flag fetch, feedback by
/// mail, and Help links that stay on ShellX. Every test that touches defaults
/// uses a private suite it removes, never the test host's `.standard`.
struct ShellXNoPhoneHomeTests {
    /// Records what analytics would have sent, from any queue.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []

        func record(_ name: String) {
            lock.lock()
            recorded.append(name)
            lock.unlock()
        }

        var names: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }
    }

    /// No XCTest markers and the debug opt-in set, so neither the XCTest guard
    /// nor the debug-build gate stops capture: only the launch telemetry
    /// switch (`TelemetrySettings.enabledForCurrentLaunch`) can.
    @Test func analyticsNeverCaptureWithTheLaunchTelemetrySwitch() throws {
        let suiteName = "shellx.no-phone-home.analytics.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recorder = Recorder()
        let workQueue = DispatchQueue(label: "shellx.tests.no-phone-home.analytics")
        let analytics = PostHogAnalytics(
            workQueue: workQueue,
            userDefaults: defaults,
            capturePostHog: { event, _ in recorder.record(event) },
            flushPostHog: { recorder.record("flush") },
            contextCalls: PostHogContextCalls(register: { _ in recorder.record("register") }),
            environment: ["CMUX_POSTHOG_ENABLE": "1"]
        )

        analytics.trackActive(reason: "shellx-test")
        analytics.trackDailyActive(reason: "shellx-test")
        analytics.trackHourlyActive(reason: "shellx-test")
        analytics.capture("shellx_test_event", properties: ["source": "test"])
        analytics.register(["plan": "test"])
        analytics.identify(accountID: "shellx-test-account")
        workQueue.sync {}

        #expect(TelemetrySettings.enabledForCurrentLaunch == false)
        #expect(analytics.isCaptureEnabled == false)
        #expect(recorder.names.isEmpty, Comment(rawValue: recorder.names.joined(separator: ", ")))
        #expect(defaults.persistentDomain(forName: suiteName)?.isEmpty ?? true)
    }

    /// Release builds capture nothing even with telemetry consent and the
    /// debug opt-in; only a debug build honors `CMUX_POSTHOG_ENABLE=1`.
    @Test func releaseBuildsNeverCapture() {
        let optIn = ["CMUX_POSTHOG_ENABLE": "1"]
        #expect(PostHogAnalytics.buildAllowsCapture(environment: optIn, isDebugBuild: false) == false)
        #expect(PostHogAnalytics.buildAllowsCapture(environment: [:], isDebugBuild: false) == false)
        #expect(PostHogAnalytics.buildAllowsCapture(environment: [:], isDebugBuild: true) == false)
    }

    /// The default remote loader and a started flag store never reach a
    /// control plane, with or without telemetry consent.
    @MainActor
    @Test func remoteFeatureFlagsAreNeverFetched() async throws {
        let suiteName = "shellx.no-phone-home.flags.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(CmuxFeatureFlags.postHogControlPlaneRequest(telemetryEnabled: true, defaults: defaults) == nil)
        #expect(CmuxFeatureFlags.postHogControlPlaneRequest(telemetryEnabled: false, defaults: defaults) == nil)
        #expect(await CmuxFeatureFlags.loadPostHogControlPlaneFlags(
            distinctID: "shellx-test",
            personProperties: [:]
        ) == nil)

        // Not pinned to local values, telemetry on, default loader: start()
        // runs the refresh, which must leave no remote value behind.
        let flags = CmuxFeatureFlags(defaults: defaults, telemetryEnabled: true, pinsFlagsToLocalValues: false)
        flags.start()
        for _ in 0..<20 { await Task.yield() }

        for definition in CmuxFeatureFlags.allFlags {
            #expect(flags.remoteValue(for: definition) == nil, Comment(rawValue: definition.key))
        }
        let stored = defaults.persistentDomain(forName: suiteName) ?? [:]
        #expect(!stored.keys.contains(where: { $0.hasPrefix("cmux.flags.remote.") }))
    }

    @Test func feedbackUsesMail() {
        #expect(FeedbackComposerSettings.submissionURL.absoluteString == "mailto:phule9225@gmail.com")
        #expect(FeedbackComposerSettings().endpointURL(environment: [:]) == nil)
    }

    // Literals, not ShellXBrand: this test target does not link ShellXBrand.
    @Test func helpMenuLinksStayOnShellX() {
        #expect(CmuxHelpResource.website.url.absoluteString == "https://shellx.pro")
        #expect(CmuxHelpResource.sourceCode.url.absoluteString == "https://github.com/lephus/shellx")
    }

    @Test func writtenConfigSchemaIsNotUpstream() {
        #expect(CmuxSettingsFileStore.schemaURLString == "https://shellx.pro/schema/shellx.json")
    }
}
#endif
