public import CMUXMobileCore
public import Foundation

/// Crash reporting entry point for the iOS app.
///
/// ShellX links no Sentry SDK and sends no crash telemetry, so this keeps the
/// composition root's calls compiling and only purges any crash cache an
/// earlier cmux build left behind.
public struct MobileCrashReporter {
    private let cachePurger: SentryCachePurger

    /// Creates a mobile crash reporter.
    public init() {
        self.init(cachePurger: SentryCachePurger())
    }

    init(cachePurger: SentryCachePurger) {
        self.cachePurger = cachePurger
    }

    #if os(iOS)
    /// Formerly paused session replay during scrolls; a no-op in ShellX.
    @MainActor
    public static func setReplayCapturePaused(_ paused: Bool) {}
    #endif

    /// Starts nothing. Purges a stale crash cache unless this is a test run.
    public func startIfEnabled(
        consent: any AnalyticsConsentProviding,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        notificationCenter: NotificationCenter = .default,
        revocationWatcher: RevocationWatcher,
        replayMaskedViewClasses: [AnyClass]? = nil,
        purgeCache: (@Sendable () -> Void)? = nil
    ) {
        guard !isTestRun(environment: environment) else { return }
        let cachePurger = self.cachePurger
        (purgeCache ?? { cachePurger.purge() })()
    }

    /// Process-lifetime telemetry-consent watcher used by the app composition root.
    public typealias RevocationWatcher = MobileCrashRevocationWatcher

    private func isTestRun(environment: [String: String]) -> Bool {
        for key in Self.testEnvironmentKeys where environment[key] != nil {
            return true
        }
        return environment.keys.contains { key in
            Self.testEnvironmentKeyPrefixes.contains { key.hasPrefix($0) }
        }
    }

    private static let testEnvironmentKeys = [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCTestSessionIdentifier",
    ]
    private static let testEnvironmentKeyPrefixes = [
        "XCInjectBundle",
        "CMUX_UITEST_",
    ]
}
