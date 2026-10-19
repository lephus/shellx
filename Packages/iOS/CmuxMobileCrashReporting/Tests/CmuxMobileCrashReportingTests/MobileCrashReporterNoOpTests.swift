import CMUXMobileCore
import Foundation
import Testing
@testable import CmuxMobileCrashReporting

/// ShellX starts no crash reporter; launching only purges a stale cache.
@Suite struct MobileCrashReporterNoOpTests {
    @Test func startPurgesTheStaleCacheOutsideTests() {
        let purges = PurgeCounter()
        MobileCrashReporter().startIfEnabled(
            consent: CrashTestToggleConsent(enabled: true),
            environment: [:],
            revocationWatcher: MobileCrashReporter.RevocationWatcher(),
            purgeCache: { purges.increment() }
        )
        #expect(purges.value == 1)
    }

    @Test func testRunsTouchNothing() {
        let purges = PurgeCounter()
        MobileCrashReporter().startIfEnabled(
            consent: CrashTestToggleConsent(enabled: true),
            environment: ["XCTestConfigurationFilePath": "/tmp/x"],
            revocationWatcher: MobileCrashReporter.RevocationWatcher(),
            purgeCache: { purges.increment() }
        )
        #expect(purges.value == 0)
    }
}

private final class PurgeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    func increment() { lock.withLock { stored += 1 } }
}
