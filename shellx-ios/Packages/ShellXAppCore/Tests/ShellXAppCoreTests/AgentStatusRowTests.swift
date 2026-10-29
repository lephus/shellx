import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The "Agents · N" rows: how long each state has lasted, and in which order they show.
final class AgentStatusRowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let nowMs: Int64 = 1_700_000_000_000

    func testElapsedClampsNegative() {
        // The Mac's clock runs ahead of the phone's: the state seems to begin in the future.
        let ahead = liveSession("s1", activity: nowMs, since: nowMs + 5_000)
        XCTAssertEqual(AgentStatusRow(session: ahead, now: now).elapsed, .zero)

        let running = liveSession("s1", activity: nowMs, since: nowMs - 240_000)
        XCTAssertEqual(AgentStatusRow(session: running, now: now).elapsed, .seconds(240))
    }

    func testElapsedNilWithoutSince() {
        let row = AgentStatusRow(session: liveSession("s1", activity: nowMs, since: nil), now: now)
        XCTAssertNil(row.elapsed)
    }

    func testRowsOrderNeedsYouThenRunningThenDone() {
        let sessions = [
            liveSession("done-new", state: .idle, activity: 900),
            liveSession("running-old", state: .working, activity: 100),
            liveSession("unknown", state: .other("paused"), activity: 1_000),
            liveSession("needs-you", state: .needsInput, activity: 50),
            liveSession("running-new", mac: "m2", online: false, state: .working, activity: 500),
            liveSession("done-old", state: .idle, activity: 200),
        ]

        let rows = AgentStatusRow.rows(sessions, now: now)

        XCTAssertEqual(
            rows.map(\.ref.sessionId), ["needs-you", "running-new", "running-old", "done-new", "done-old", "unknown"])
        let offline = rows[1]
        XCTAssertEqual(offline.machineName, "Mac m2")
        XCTAssertFalse(offline.online)
        XCTAssertEqual(offline.state, .working)
        XCTAssertEqual(offline.id, sessions[4].ref)
    }
}
