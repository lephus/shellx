import CMUXMobileCore
import CmuxSentryReporting
import Foundation
import Testing

/// ShellX links no Sentry SDK: ingesting failures, even a sustained outage,
/// never reads the diagnostic ring for an incident attachment.
@Suite struct TransportSentryReporterNoOpTests {
    @Test func ingestNeverExportsTheRing() async throws {
        let exports = ExportCounter()
        let reporter = TransportSentryReporter(
            role: .macHost,
            exportRing: { await exports.increment(); return Data() },
            incidentConfiguration: .init(captureIndividualFailures: true),
            logsPerHour: 100
        )
        for second in UInt64(1)...UInt64(600) {
            reporter.ingest(DiagnosticEvent(
                code: .transportDialFailed,
                tNanos: second * 1_000_000_000,
                a: DiagnosticTransportKind.iroh.rawValue,
                b: DiagnosticFailureKind.policyUnavailable.rawValue,
                c: 7
            ))
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await exports.count == 0)
    }
}

private actor ExportCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
