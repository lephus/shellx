public import CMUXMobileCore
public import Foundation

/// ShellX links no Sentry SDK. The reporter keeps upstream's construction and
/// `ingest(_:)` entry point so composition roots still compile, but it sends
/// nothing: diagnostic events stay in the local ring only.
public final class TransportSentryReporter: Sendable {
    /// Severity a delivered line would have carried. Kept for API stability.
    public enum LogLevel: Sendable, Equatable {
        case info
        case warning
        case error
    }

    /// Creates a reporter that never delivers.
    ///
    /// - Parameters:
    ///   - role: The producing runtime; unused.
    ///   - exportRing: Snapshot of the diagnostic ring; never read.
    ///   - incidentConfiguration: Capture-gate thresholds; unused.
    ///   - logsPerHour: Structured log budget; unused.
    public init(
        role: DiagnosticRuntimeRole,
        exportRing: @escaping @Sendable () async -> Data,
        incidentConfiguration: TransportIncidentPolicy.Configuration = .init(captureIndividualFailures: false),
        logsPerHour: Int = 0
    ) {}

    /// Accepts one diagnostic event and drops it.
    public func ingest(_ event: DiagnosticEvent) {}
}
