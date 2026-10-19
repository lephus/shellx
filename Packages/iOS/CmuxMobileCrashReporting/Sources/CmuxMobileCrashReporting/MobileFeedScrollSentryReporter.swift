public import CMUXMobileCore

/// Formerly linked a Feed callback stall to a Sentry event. ShellX sends no
/// telemetry, so ``report(_:)`` never captures and returns no event id.
@MainActor
public struct MobileFeedScrollSentryReporter {
    private let consent: any AnalyticsConsentProviding

    public init(consent: any AnalyticsConsentProviding) {
        self.consent = consent
    }

    /// Returns `nil`: nothing is captured.
    public func report(_ anomaly: MobileFeedScrollAnomaly) -> String? {
        nil
    }
}
