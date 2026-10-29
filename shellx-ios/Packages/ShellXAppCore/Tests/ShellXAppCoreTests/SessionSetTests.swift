import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

final class SessionSetTests: XCTestCase {
    func testUpsertAndRemove() {
        var set = SessionSet()
        set.reset(revision: 1, sessions: [agentSession("s1", lastActivityMs: 100), agentSession("s2", lastActivityMs: 300)])
        // Most recent activity first.
        XCTAssertEqual(set.sessions.map(\.sessionId), ["s2", "s1"])

        let s1Busy = agentSession("s1", state: .needsInput, lastActivityMs: 500)
        XCTAssertEqual(set.apply(revision: 2, upserted: [s1Busy], removed: ["s2"]), .applied)
        XCTAssertEqual(set.revision, 2)
        XCTAssertEqual(set.sessions, [s1Busy])

        XCTAssertEqual(set.apply(revision: 3, upserted: [agentSession("s3", lastActivityMs: 200)], removed: []), .applied)
        XCTAssertEqual(set.sessions.map(\.sessionId), ["s1", "s3"])

        XCTAssertEqual(set.apply(revision: 3, upserted: [], removed: ["s1"]), .ignored)
        XCTAssertEqual(set.sessions.map(\.sessionId), ["s1", "s3"])
    }

    func testListAnswerReplacesRevisionAfterMacRestart() {
        var set = SessionSet()
        set.reset(revision: 42, sessions: [agentSession("s1")])

        // The Mac app restarted: its `agent.sessions` revision starts at 0 again. The answer replaces
        // the set's revision, so the next change (1) applies instead of looking already seen.
        set.reset(revision: 0, sessions: [agentSession("s2")])
        XCTAssertEqual(set.revision, 0)
        XCTAssertEqual(set.apply(revision: 1, upserted: [agentSession("s3")], removed: []), .applied)
        XCTAssertEqual(set.sessions.map(\.sessionId).sorted(), ["s2", "s3"])
    }

    func testGapReported() {
        var set = SessionSet()
        set.reset(revision: 4, sessions: [agentSession("s1")])

        XCTAssertEqual(set.apply(revision: 6, upserted: [agentSession("s2")], removed: ["s1"]), .gap)
        XCTAssertEqual(set.revision, 4)
        XCTAssertEqual(set.sessions.map(\.sessionId), ["s1"])
        XCTAssertEqual(set.apply(revision: 4, upserted: [agentSession("s2")], removed: []), .ignored)
    }
}
