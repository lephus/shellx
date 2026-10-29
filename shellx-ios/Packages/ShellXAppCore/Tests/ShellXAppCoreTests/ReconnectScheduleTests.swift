import XCTest

@testable import ShellXAppCore

final class ReconnectScheduleTests: XCTestCase {
    func testDelaysGrowAndCapAt30s() {
        let schedule = ReconnectSchedule.standard
        let delays = (1...10).map { seconds(schedule.delay(afterFailures: $0, jitter: 0)) }
        XCTAssertEqual(delays, [0.5, 1, 2, 4, 8, 15, 30, 30, 30, 30])
        XCTAssertEqual(schedule.delay(afterFailures: 1000, jitter: 0), .seconds(30))
        XCTAssertEqual(schedule.delay(afterFailures: 0, jitter: 0), .zero)
    }

    func testJitterWithin20Percent() {
        let schedule = ReconnectSchedule.standard
        for failures in 1...10 {
            let base = seconds(schedule.delay(afterFailures: failures, jitter: 0))
            for jitter in stride(from: -1.0, through: 1.0, by: 0.125) {
                let delay = seconds(schedule.delay(afterFailures: failures, jitter: jitter))
                XCTAssertLessThanOrEqual(abs(delay - base), base * 0.2 + 1e-9, "failures \(failures), jitter \(jitter)")
            }
            XCTAssertEqual(seconds(schedule.delay(afterFailures: failures, jitter: 1)), base * 1.2, accuracy: 1e-9)
            XCTAssertEqual(seconds(schedule.delay(afterFailures: failures, jitter: -1)), base * 0.8, accuracy: 1e-9)
            // Out-of-range jitter is clamped, never more than 20 %.
            XCTAssertEqual(seconds(schedule.delay(afterFailures: failures, jitter: 7)), base * 1.2, accuracy: 1e-9)
            XCTAssertEqual(seconds(schedule.delay(afterFailures: failures, jitter: -7)), base * 0.8, accuracy: 1e-9)
        }
        XCTAssertLessThanOrEqual(schedule.delay(afterFailures: 99, jitter: 1), .seconds(36))
    }
}
