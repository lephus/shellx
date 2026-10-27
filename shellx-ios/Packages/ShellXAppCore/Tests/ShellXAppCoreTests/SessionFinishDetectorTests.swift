import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// Which sessions just finished: working or waiting on the user before, idle now.
final class SessionFinishDetectorTests: XCTestCase {
    private func session(_ id: String, _ state: AgentState, since: Int64?) -> AgentSession {
        agentSession(id, state: state, stateSinceMs: since)
    }

    private func roundTrip(_ detector: SessionFinishDetector) throws -> SessionFinishDetector {
        try JSONDecoder().decode(SessionFinishDetector.self, from: JSONEncoder().encode(detector))
    }

    func testWorkingToIdleIsFinished() {
        var detector = SessionFinishDetector()
        let first = detector.observe(
            machineID: "m1", sessions: [session("s1", .working, since: 1), session("s2", .needsInput, since: 1)])
        XCTAssertEqual(first, [])
        // Another Mac's list leaves m1's alone.
        XCTAssertEqual(detector.observe(machineID: "m2", sessions: []), [])

        let finished = detector.observe(
            machineID: "m1", sessions: [session("s1", .idle, since: 2), session("s2", .idle, since: 3)])

        XCTAssertEqual(finished.map(\.sessionId), ["s1", "s2"])
        XCTAssertEqual(finished.map(\.machineID), ["m1", "m1"])
        XCTAssertEqual(finished.first?.agent, "claude")
        XCTAssertEqual(finished.first?.workspaceTitle, "shellx")
    }

    func testFinishedWhileAppClosedDetectedFromSaved() throws {
        var detector = SessionFinishDetector()
        _ = detector.observe(machineID: "m1", sessions: [session("s1", .working, since: 1)])

        // The app closes; the next launch reads the saved detector, then sees the Mac's list.
        var restored = try roundTrip(detector)
        let finished = restored.observe(machineID: "m1", sessions: [session("s1", .idle, since: 5)])

        XCTAssertEqual(finished.map(\.sessionId), ["s1"])
    }

    func testSameFinishNotRepeatedAfterResync() throws {
        var detector = SessionFinishDetector()
        _ = detector.observe(machineID: "m1", sessions: [session("s1", .working, since: 1)])
        XCTAssertEqual(detector.observe(machineID: "m1", sessions: [session("s1", .idle, since: 2)]).count, 1)

        // A resync (a reconnect, a restarted Mac app) replays an older list, then the same finish.
        _ = detector.observe(machineID: "m1", sessions: [session("s1", .working, since: 1)])
        XCTAssertEqual(detector.observe(machineID: "m1", sessions: [session("s1", .idle, since: 2)]), [])
        // Also after a relaunch.
        var restored = try roundTrip(detector)
        _ = restored.observe(machineID: "m1", sessions: [session("s1", .working, since: 1)])
        XCTAssertEqual(restored.observe(machineID: "m1", sessions: [session("s1", .idle, since: 2)]), [])

        // The next turn's finish is a new one.
        _ = restored.observe(machineID: "m1", sessions: [session("s1", .working, since: 3)])
        XCTAssertEqual(restored.observe(machineID: "m1", sessions: [session("s1", .idle, since: 4)]).count, 1)
    }

    func testIdleToIdleNotFinished() {
        var detector = SessionFinishDetector()
        XCTAssertEqual(detector.observe(machineID: "m1", sessions: [session("s1", .idle, since: 1)]), [])
        XCTAssertEqual(detector.observe(machineID: "m1", sessions: [session("s1", .idle, since: 2)]), [])
        // A session first seen idle, and a session that ended instead of finishing.
        _ = detector.observe(machineID: "m1", sessions: [session("s1", .idle, since: 2), session("s2", .working, since: 1)])
        let changed = detector.observe(
            machineID: "m1", sessions: [session("s2", .ended, since: 3), session("s3", .idle, since: 3)])
        XCTAssertEqual(changed, [])
    }

    func testForgetsMacsNoLongerPaired() {
        var detector = SessionFinishDetector()
        _ = detector.observe(machineID: "m1", sessions: [session("s1", .working, since: 1)])
        _ = detector.observe(machineID: "m2", sessions: [session("s1", .working, since: 1)])

        detector.retain(machineIDs: ["m2"])

        XCTAssertEqual(detector.observe(machineID: "m1", sessions: [session("s1", .idle, since: 2)]), [])
        XCTAssertEqual(detector.observe(machineID: "m2", sessions: [session("s1", .idle, since: 2)]).count, 1)
    }
}
