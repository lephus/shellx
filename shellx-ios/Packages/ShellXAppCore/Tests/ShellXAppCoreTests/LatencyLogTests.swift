import XCTest

@testable import ShellXAppCore

final class LatencyLogTests: XCTestCase {
    func testPercentilesOverLast200() {
        let log = LatencyLog()
        XCTAssertNil(log.summary(.replyRoundTrip))
        for ms in 1...300 { log.record(.replyRoundTrip, .milliseconds(ms)) }
        log.record(.firstWord, .milliseconds(80))

        // Only 101...300 ms count: nearest-rank p50 is the 100th value, p95 the 190th.
        XCTAssertEqual(
            log.summary(.replyRoundTrip),
            LatencySummary(count: 200, p50: .milliseconds(200), p95: .milliseconds(290)))
        XCTAssertEqual(log.summary(.firstWord), LatencySummary(count: 1, p50: .milliseconds(80), p95: .milliseconds(80)))
        XCTAssertNil(log.summary(.pendingArrival))
    }

    func testNegativeDurationRecordedAsZero() {
        let log = LatencyLog()
        log.record(.pendingArrival, .milliseconds(-40))
        XCTAssertEqual(log.summary(.pendingArrival), LatencySummary(count: 1, p50: .zero, p95: .zero))
    }

    func testRecordingFromManyThreads() async {
        let log = LatencyLog()
        await withTaskGroup(of: Void.self) { group in
            for task in 0..<8 {
                group.addTask {
                    for ms in 0..<50 { log.record(.sessionChangeArrival, .milliseconds(task * 50 + ms)) }
                }
            }
        }
        XCTAssertEqual(log.summary(.sessionChangeArrival)?.count, 200)
    }
}
