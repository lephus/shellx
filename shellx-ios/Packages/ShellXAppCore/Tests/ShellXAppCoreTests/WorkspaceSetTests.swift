import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

final class WorkspaceSetTests: XCTestCase {
    func testApplyNextRevision() {
        var set = WorkspaceSet()
        set.reset(revision: 3, workspaces: [linkWorkspace("a", order: 0)])

        let b = linkWorkspace("b", order: 1)
        XCTAssertEqual(set.apply(revision: 4, upserted: [b], removed: []), .applied)
        XCTAssertEqual(set.revision, 4)
        XCTAssertEqual(set.workspaces.map(\.workspaceId), ["ws-a", "ws-b"])

        // An upsert replaces the workspace with the same id, with all its terminals.
        let withTerminals = linkWorkspace("a", order: 0, terminals: [linkTerminal("t1"), linkTerminal("t2", order: 1)])
        XCTAssertEqual(set.apply(revision: 5, upserted: [withTerminals], removed: ["ws-b"]), .applied)
        XCTAssertEqual(set.workspaces, [withTerminals])
        XCTAssertEqual(set.workspace("ws-a")?.terminals.map(\.terminalId), ["t1", "t2"])
        XCTAssertNil(set.workspace("ws-b"))
    }

    func testIgnoreOldRevision() {
        var set = WorkspaceSet()
        set.reset(revision: 4, workspaces: [linkWorkspace("a")])

        XCTAssertEqual(set.apply(revision: 4, upserted: [linkWorkspace("b")], removed: ["ws-a"]), .ignored)
        XCTAssertEqual(set.apply(revision: 2, upserted: [], removed: ["ws-a"]), .ignored)
        XCTAssertEqual(set.revision, 4)
        XCTAssertEqual(set.workspaces.map(\.workspaceId), ["ws-a"])
    }

    func testGapReported() {
        var set = WorkspaceSet()
        set.reset(revision: 4, workspaces: [linkWorkspace("a")])

        XCTAssertEqual(set.apply(revision: 6, upserted: [linkWorkspace("b")], removed: ["ws-a"]), .gap)
        XCTAssertEqual(set.revision, 4)
        XCTAssertEqual(set.workspaces.map(\.workspaceId), ["ws-a"])
        // The change that was skipped is not mistaken for an old one afterwards.
        XCTAssertEqual(set.apply(revision: 5, upserted: [linkWorkspace("b")], removed: []), .applied)
    }

    func testSortedByOrder() {
        var set = WorkspaceSet()
        set.reset(
            revision: 1,
            workspaces: [linkWorkspace("c", order: 2), linkWorkspace("a", order: 0), linkWorkspace("b", order: 1)])
        XCTAssertEqual(set.workspaces.map(\.workspaceId), ["ws-a", "ws-b", "ws-c"])

        // The Mac moved "a" to the end: the upsert re-sorts the list.
        XCTAssertEqual(set.apply(revision: 2, upserted: [linkWorkspace("a", order: 5)], removed: []), .applied)
        XCTAssertEqual(set.workspaces.map(\.workspaceId), ["ws-b", "ws-c", "ws-a"])

        // The same position (two windows may each count from 0) falls back to the id.
        var tie = WorkspaceSet(revision: 1, workspaces: [linkWorkspace("z", order: 0), linkWorkspace("y", order: 0)])
        XCTAssertEqual(tie.workspaces.map(\.workspaceId), ["ws-y", "ws-z"])
        XCTAssertEqual(tie.apply(revision: 2, upserted: [], removed: ["ws-y"]), .applied)
        XCTAssertEqual(tie.workspaces.map(\.workspaceId), ["ws-z"])
    }

    func testListAnswerReplacesRevisionAfterMacRestart() {
        var set = WorkspaceSet()
        set.reset(revision: 42, workspaces: [linkWorkspace("a")])

        // The Mac app restarted: its `workspace.list` revision starts again at 0.
        set.reset(revision: 0, workspaces: [linkWorkspace("b")])
        XCTAssertEqual(set.revision, 0)
        XCTAssertEqual(set.apply(revision: 1, upserted: [linkWorkspace("c", order: 1)], removed: []), .applied)
        XCTAssertEqual(set.workspaces.map(\.workspaceId), ["ws-b", "ws-c"])
    }
}
