import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The name each session row shows: its own title, de-duplicated within one list.
final class SessionNameTests: XCTestCase {
    private func titled(_ id: String, _ title: String?) -> AgentSession {
        var s = agentSession(id)
        s.title = title
        return s
    }

    private func onMac(_ machineID: String, _ session: AgentSession) -> MachineSession {
        MachineSession(machineID: machineID, machineName: machineID, online: true, session: session)
    }

    func testCleanedKeepsAPlainTitle() {
        XCTAssertEqual(SessionName.cleaned("Sửa nút ＋ trên iOS 🚀"), "Sửa nút ＋ trên iOS 🚀")
    }

    func testCleanedTakesTheFirstNonBlankLineAndCollapsesSpaces() {
        XCTAssertEqual(SessionName.cleaned("\n  \n  Viết test   SessionSet \nmore"), "Viết test SessionSet")
    }

    func testCleanedDropsTagsAndALeadingSlashCommand() {
        XCTAssertEqual(SessionName.cleaned("<command-message>brainstorm</command-message>"), "brainstorm")
        XCTAssertEqual(SessionName.cleaned("/review fix the login bug"), "fix the login bug")
        XCTAssertNil(SessionName.cleaned("<command-name>/clear</command-name>"))
    }

    func testCleanedKeepsAPathThatStartsWithASlash() {
        XCTAssertEqual(SessionName.cleaned("/Users/x/app crashes"), "/Users/x/app crashes")
    }

    func testCleanedDropsATagTheMacCutInTheMiddle() {
        XCTAssertEqual(SessionName.cleaned("fix the login <command-mess"), "fix the login")
        XCTAssertNil(SessionName.cleaned("<command-mess"))
    }

    func testCleanedTriesTheNextLineWhenTheFirstIsOnlyTags() {
        XCTAssertEqual(SessionName.cleaned("<command-name>/clear</command-name>\n  \nfix the login"), "fix the login")
    }

    func testCleanedIsNilForNothing() {
        XCTAssertNil(SessionName.cleaned(nil))
        XCTAssertNil(SessionName.cleaned("   \n "))
    }

    func testBaseFallsBackToAgentAndTime() {
        var s = agentSession("s1", lastActivityMs: 1_793_284_320_000)  // 2026-10-29 14:32:00 UTC
        s.title = nil
        XCTAssertEqual(SessionName.base(of: s, timeZone: TimeZone(identifier: "UTC")!), "Claude Code · 14:32")
        s.lastActivityMs = nil
        s.stateSinceMs = nil
        XCTAssertEqual(SessionName.base(of: s), "Claude Code")
    }

    func testDistinctNumbersEqualNamesInSessionOrder() {
        let sessions = [
            onMac("m1", titled("s3", "Fix bug")), onMac("m1", titled("s1", "Fix bug")),
            onMac("m1", titled("s2", "Fix bug")), onMac("m1", titled("s4", "Docs")),
        ]
        let names = SessionName.distinct(sessions)
        func name(_ id: String) -> String? { names[sessions.first { $0.session.sessionId == id }!.ref] }
        XCTAssertEqual(name("s1"), "Fix bug")
        XCTAssertEqual(name("s2"), "Fix bug · #2")
        XCTAssertEqual(name("s3"), "Fix bug · #3")
        XCTAssertEqual(name("s4"), "Docs")
    }

    func testDistinctKeepsTheSameSessionIdOnTwoMacsApart() {
        let a = onMac("m1", titled("s1", "Fix bug"))
        let b = onMac("m2", titled("s1", "Fix bug"))
        let names = SessionName.distinct([b, a])
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(names[a.ref], "Fix bug")
        XCTAssertEqual(names[b.ref], "Fix bug · #2")
    }
}
