import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// Which running session the composer sends to when the user picked none (plan decision D7).
final class PreferredTargetTests: XCTestCase {
    func testLastUsedWinsWhileLive() {
        let sessions = [liveSession("new", activity: 300), liveSession("old", activity: 100)]
        let old = SessionRef(machineID: "m1", sessionId: "old", agent: "claude", workspaceTitle: "renamed since")

        let target = sessions.preferredTarget(lastUsed: old, defaultMachineID: "m1")
        XCTAssertEqual(target, old)
        XCTAssertEqual(target?.workspaceTitle, "shellx", "the live session's labels, not the remembered ones")

        let gone = SessionRef(machineID: "m1", sessionId: "gone", agent: "claude", workspaceTitle: "shellx")
        XCTAssertEqual(sessions.preferredTarget(lastUsed: gone, defaultMachineID: "m1")?.sessionId, "new")
    }

    func testDefaultMacMostRecentNext() {
        let sessions = [
            liveSession("m1-old", mac: "m1", activity: 100),
            liveSession("m2-newest", mac: "m2", activity: 500),
            liveSession("m1-new", mac: "m1", activity: 200),
            liveSession("m1-quiet", mac: "m1", activity: nil),
        ]

        XCTAssertEqual(sessions.preferredTarget(lastUsed: nil, defaultMachineID: "m1")?.sessionId, "m1-new")
        XCTAssertEqual(sessions.preferredTarget(lastUsed: nil, defaultMachineID: "m2")?.sessionId, "m2-newest")
        // No default, or a default Mac without sessions: the newest anywhere.
        XCTAssertEqual(sessions.preferredTarget(lastUsed: nil, defaultMachineID: nil)?.sessionId, "m2-newest")
        XCTAssertEqual(sessions.preferredTarget(lastUsed: nil, defaultMachineID: "m3")?.sessionId, "m2-newest")
    }

    func testOfflineAndEndedNeverTargets() {
        let sessions = [
            liveSession("offline", mac: "m1", online: false, activity: 900),
            liveSession("ended", mac: "m2", state: .ended, activity: 800),
            liveSession("running", mac: "m2", activity: 100),
        ]
        let offline = sessions[0].ref
        let ended = sessions[1].ref

        XCTAssertEqual(sessions.preferredTarget(lastUsed: nil, defaultMachineID: "m1")?.sessionId, "running")
        XCTAssertEqual(sessions.preferredTarget(lastUsed: offline, defaultMachineID: "m1")?.sessionId, "running")
        XCTAssertEqual(sessions.preferredTarget(lastUsed: ended, defaultMachineID: "m2")?.sessionId, "running")
    }

    func testNoLiveSessionGivesNil() {
        XCTAssertNil([MachineSession]().preferredTarget(lastUsed: nil, defaultMachineID: "m1"))
        let unusable = [
            liveSession("offline", online: false, activity: 900),
            liveSession("ended", state: .ended, activity: 800),
        ]
        XCTAssertNil(unusable.preferredTarget(lastUsed: unusable[0].ref, defaultMachineID: "m1"))
    }
}
