import CmuxFeedback
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV

/// ShellX never phones home: no telemetry, no remote flag fetch, feedback by
/// mail, and Help links that stay on ShellX.
struct ShellXNoPhoneHomeTests {
    @MainActor
    @Test func telemetryAndRemoteFlagsAreOff() {
        #expect(TelemetrySettings.enabledForCurrentLaunch == false)
        #expect(CmuxFeatureFlags.remoteConfigFetchEnabled == false)
        #expect(CmuxFeatureFlags.postHogControlPlaneRequest(telemetryEnabled: true) == nil)
        #expect(CmuxFeatureFlags.postHogControlPlaneRequest(telemetryEnabled: false) == nil)
    }

    @Test func analyticsNeverCapture() {
        #expect(PostHogAnalytics.shared.isCaptureEnabled == false)
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
