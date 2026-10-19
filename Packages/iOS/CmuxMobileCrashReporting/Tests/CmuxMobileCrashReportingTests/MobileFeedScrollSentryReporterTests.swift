import CMUXMobileCore
import Foundation
import Testing
@testable import CmuxMobileCrashReporting

@Suite @MainActor struct MobileFeedScrollSentryReporterTests {
    @Test func neverCapturesEvenWithConsent() {
        let anomaly = MobileFeedScrollAnomaly(
            windowID: "2dcadcc5-4e91-4343-a48e-896889eb1e48", maxGapMilliseconds: 120,
            callbackCount: 600, itemCount: 400
        )
        for enabled in [true, false] {
            let reporter = MobileFeedScrollSentryReporter(consent: CrashTestToggleConsent(enabled: enabled))
            #expect(reporter.report(anomaly) == nil)
        }
    }
}
