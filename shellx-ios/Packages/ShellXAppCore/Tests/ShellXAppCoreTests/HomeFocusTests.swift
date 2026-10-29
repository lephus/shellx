import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// Which group of the home each session goes in.
final class HomeFocusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var nowMs: Int64 { Int64(now.timeIntervalSince1970 * 1000) }

    private func ms(ago seconds: Double) -> Int64 { nowMs - Int64(seconds * 1000) }

    private func on(_ machine: String, _ session: AgentSession) -> MachineSession {
        MachineSession(machineID: machine, machineName: machine, online: true, session: session)
    }

    private func request(_ id: String, machine: String = "m1", workspace: String = "shellx", agent: String = "claude", preview: String? = nil)
        -> MachinePendingItem
    {
        var item = pendingItem(id, workspace: workspace)
        item.agent = agent
        item.toolInputPreview = preview
        return MachinePendingItem(machineID: machine, machineName: machine, item: item, actionable: true)
    }

    private func make(
        _ sessions: [MachineSession], pending: [MachinePendingItem] = [], finished: [String: [String: Date]] = [:]
    ) -> HomeFocus {
        HomeFocus.make(
            sessions: sessions, pending: pending, finished: finished, now: now, timeZone: TimeZone(identifier: "UTC")!)
    }

    private func ids(_ items: [FocusItem]) -> [String] { items.map(\.session.session.sessionId) }

    func testEachSessionGoesToItsGroup() {
        let sessions = [
            on("m1", agentSession("s1", state: .needsInput)),
            on("m1", agentSession("s2", state: .working)),
            on("m1", agentSession("s3", state: .idle)),
            on("m1", agentSession("s4", state: .idle)),
            on("m1", agentSession("s5", state: .ended, stateSinceMs: ms(ago: 3600))),
        ]
        let focus = make(sessions, finished: ["m1": ["s3": now.addingTimeInterval(-600)]])
        XCTAssertEqual(ids(focus.needsYou), ["s1"])
        XCTAssertEqual(ids(focus.running), ["s2"])
        XCTAssertEqual(ids(focus.justDone), ["s3"])
        XCTAssertEqual(ids(focus.ended), ["s5"])
        XCTAssertEqual(focus.justDone.first?.finishedAt, now.addingTimeInterval(-600))
        XCTAssertFalse(focus.isQuiet)
    }

    func testQuietWhenOnlyEndedOrNothing() {
        XCTAssertTrue(make([]).isQuiet)
        XCTAssertTrue(HomeFocus.empty.isQuiet)
        let ended = on("m1", agentSession("s", state: .ended, stateSinceMs: ms(ago: 5)))
        XCTAssertTrue(make([ended]).isQuiet)
    }

    func testJustDoneLastsAnHour() {
        let s = [on("m1", agentSession("s", state: .idle))]
        XCTAssertEqual(ids(make(s, finished: ["m1": ["s": now.addingTimeInterval(-3599)]]).justDone), ["s"])
        XCTAssertEqual(ids(make(s, finished: ["m1": ["s": now.addingTimeInterval(-3600)]]).justDone), [])
    }

    func testEndedLastsTwelveHours() {
        func ended(_ age: Double) -> [FocusItem] {
            make([on("m1", agentSession("s", state: .ended, stateSinceMs: ms(ago: age)))]).ended
        }
        XCTAssertEqual(ids(ended(43_199)), ["s"])
        XCTAssertEqual(ids(ended(43_200)), [])
    }

    func testEndedAgeFallsBackToLastActivity() {
        let s = agentSession("s", state: .ended, lastActivityMs: ms(ago: 60), stateSinceMs: nil)
        XCTAssertEqual(ids(make([on("m1", s)]).ended), ["s"])
    }

    func testEndedWithoutAnyTimeIsHidden() {
        let s = agentSession("s", state: .ended, lastActivityMs: nil, stateSinceMs: nil)
        XCTAssertTrue(make([on("m1", s)]).ended.isEmpty)
    }

    func testEndedFromAMacClockAheadShows() {
        let s = agentSession("s", state: .ended, stateSinceMs: nowMs + 300_000)
        XCTAssertEqual(ids(make([on("m1", s)]).ended), ["s"])
    }

    func testEndedIsNewestFirst() {
        let sessions = [
            on("m1", agentSession("old", state: .ended, stateSinceMs: ms(ago: 7200))),
            on("m1", agentSession("new", state: .ended, stateSinceMs: ms(ago: 60))),
            on("m1", agentSession("mid", state: .ended, stateSinceMs: ms(ago: 600))),
        ]
        XCTAssertEqual(ids(make(sessions).ended), ["new", "mid", "old"])
    }

    func testTheQuestionGoesToTheNewestWaitingSession() {
        let sessions = [
            on("m1", agentSession("a", state: .needsInput, lastActivityMs: 5)),
            on("m1", agentSession("b", state: .needsInput, lastActivityMs: 9)),
        ]
        let focus = make(sessions, pending: [request("r1", preview: "Cho phép chạy xcodebuild?\nchi tiết")])
        XCTAssertEqual(focus.needsYou.count, 2)
        XCTAssertEqual(ids(focus.needsYou), ["b", "a"])
        XCTAssertEqual(focus.needsYou[0].question, "Cho phép chạy xcodebuild?")
        XCTAssertNil(focus.needsYou[1].question)
    }

    func testTheFirstMatchingRequestKeepsTheQuestion() {
        let sessions = [on("m1", agentSession("a", state: .needsInput))]
        let focus = make(sessions, pending: [request("r1", preview: "first"), request("r2", preview: "second")])
        XCTAssertEqual(focus.needsYou.first?.question, "first")
    }

    func testARequestPromotesTheNewestLiveSession() {
        let sessions = [
            on("m1", agentSession("s", state: .working, lastActivityMs: 9)),
            on("m1", agentSession("e", state: .ended, lastActivityMs: 99)),
        ]
        let focus = make(sessions, pending: [request("r1", preview: "ok?")])
        XCTAssertEqual(ids(focus.needsYou), ["s"])
        XCTAssertEqual(focus.needsYou.first?.question, "ok?")
        XCTAssertTrue(focus.running.isEmpty)
    }

    func testARequestMatchingNoSessionMakesNoCard() {
        let focus = make([on("m1", agentSession("s"))], pending: [request("r1", workspace: "wf-123")])
        XCTAssertTrue(focus.needsYou.isEmpty)
        XCTAssertEqual(ids(focus.running), ["s"])
    }

    func testRequestsOfAnotherMacOrAgentDoNotMatch() {
        let s = on("m1", agentSession("s"))
        XCTAssertTrue(make([s], pending: [request("r1", machine: "m2")]).needsYou.isEmpty)
        XCTAssertTrue(make([s], pending: [request("r2", agent: "codex")]).needsYou.isEmpty)
    }

    func testNoSessionIsInTwoGroups() {
        let states: [AgentState] = [.idle, .working, .needsInput, .ended, .other("x")]
        for withRequest in [false, true] {
            var sessions: [MachineSession] = []
            var finished: [String: Date] = [:]
            for (i, state) in states.enumerated() {
                sessions.append(on("m1", agentSession("s\(i)", state: state, lastActivityMs: Int64(i), stateSinceMs: ms(ago: 10))))
                finished["s\(i)"] = now.addingTimeInterval(-10)
            }
            let focus = make(sessions, pending: withRequest ? [request("r")] : [], finished: ["m1": finished])
            let all = (focus.needsYou + focus.running + focus.justDone + focus.ended).map(\.id)
            XCTAssertEqual(all.count, Set(all).count)
        }
    }

    func testNamesAreDistinctAcrossTheTopGroups() {
        var a = agentSession("s1", state: .working)
        a.title = "Fix bug"
        var b = agentSession("s2", state: .needsInput)
        b.title = "Fix bug"
        let focus = make([on("m1", a), on("m1", b)])
        XCTAssertEqual(focus.running.first?.name, "Fix bug")
        XCTAssertEqual(focus.needsYou.first?.name, "Fix bug · #2")
    }

    func testTheSameSessionIdOnTwoMacsIsTwoItems() {
        let focus = make([on("m1", agentSession("s")), on("m2", agentSession("s"))])
        XCTAssertEqual(focus.running.count, 2)
        XCTAssertEqual(Set(focus.running.map(\.id)).count, 2)
        XCTAssertEqual(Set(focus.running.map(\.name)).count, 2)
    }
}
