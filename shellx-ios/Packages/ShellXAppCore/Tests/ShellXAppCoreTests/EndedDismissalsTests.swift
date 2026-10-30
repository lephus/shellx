import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The ended sessions the user took off the phone's Ended list, and how that survives a launch.
@MainActor
final class EndedDismissalsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var nowMs: Int64 { Int64(now.timeIntervalSince1970 * 1000) }

    private func ms(ago seconds: Double) -> Int64 { nowMs - Int64(seconds * 1000) }

    private func ended(_ id: String, machine: String = "m1", ago seconds: Double = 600) -> MachineSession {
        MachineSession(
            machineID: machine, machineName: machine, online: true,
            session: agentSession(id, state: .ended, stateSinceMs: ms(ago: seconds)))
    }

    private func defaults() throws -> UserDefaults {
        let suite = "EndedDismissalsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return defaults
    }

    /// A store over `defaults` whose clock stands `offset` seconds after `now`.
    private func makeStore(_ defaults: UserDefaults, at offset: TimeInterval = 0) -> EndedDismissalStore {
        let clock = now.addingTimeInterval(offset)
        return EndedDismissalStore(defaults: defaults, now: { clock })
    }

    // MARK: - The value

    func testNothingIsHiddenUntilItIsDismissed() {
        XCTAssertFalse(EndedDismissals.none.hides(ended("s")))
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s"))
        XCTAssertTrue(dismissals.hides(ended("s")))
    }

    func testADismissalIsPerMacAndPerSession() {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s", machine: "m1"))
        XCTAssertFalse(dismissals.hides(ended("s", machine: "m2")), "the same id on another Mac is another session")
        XCTAssertFalse(dismissals.hides(ended("other", machine: "m1")))
    }

    func testASessionThatEndsAgainLaterShowsAgain() {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s", ago: 3600))
        XCTAssertTrue(dismissals.hides(ended("s", ago: 3600)))
        XCTAssertFalse(dismissals.hides(ended("s", ago: 60)), "a newer end is a new ending")
    }

    func testAnEarlierEndStaysHidden() {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s", ago: 60))
        XCTAssertTrue(dismissals.hides(ended("s", ago: 3600)))
    }

    func testDismissingTwiceKeepsTheNewerEnd() {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s", ago: 60))
        dismissals.dismiss(ended("s", ago: 3600))
        XCTAssertTrue(dismissals.hides(ended("s", ago: 60)))
    }

    func testASessionWithoutAnEndTimeIsNotRemembered() {
        let session = MachineSession(
            machineID: "m1", machineName: "m1", online: true,
            session: agentSession("s", state: .ended, lastActivityMs: nil, stateSinceMs: nil))
        var dismissals = EndedDismissals.none
        dismissals.dismiss(session)
        XCTAssertEqual(dismissals, .none)
    }

    func testPruningDropsWhatTheTwelveHoursWouldHaveDropped() {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("old", ago: 43_201))
        dismissals.dismiss(ended("edge", ago: 43_200))
        dismissals.dismiss(ended("fresh", ago: 43_199))
        let pruned = dismissals.pruned(now: now)
        XCTAssertFalse(pruned.hides(ended("old", ago: 43_201)))
        XCTAssertFalse(pruned.hides(ended("edge", ago: 43_200)))
        XCTAssertTrue(pruned.hides(ended("fresh", ago: 43_199)))
        var onlyFresh = EndedDismissals.none
        onlyFresh.dismiss(ended("fresh", ago: 43_199))
        XCTAssertEqual(pruned, onlyFresh, "a Mac with nothing left is not kept either")
    }

    func testAnEndAheadOfTheClockIsKept() {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s", ago: -300))
        XCTAssertTrue(dismissals.pruned(now: now).hides(ended("s", ago: -300)))
    }

    func testItSurvivesEncoding() throws {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s", machine: "m1"))
        dismissals.dismiss(ended("t", machine: "m2", ago: 90))
        let back = try JSONDecoder().decode(EndedDismissals.self, from: JSONEncoder().encode(dismissals))
        XCTAssertEqual(back, dismissals)
        XCTAssertTrue(back.hides(ended("s", machine: "m1")))
        XCTAssertTrue(back.hides(ended("t", machine: "m2", ago: 90)))
    }

    // MARK: - The Ended list and the home's fold

    private func focus(_ sessions: [MachineSession], _ dismissed: EndedDismissals) -> HomeFocus {
        HomeFocus.make(
            sessions: sessions, pending: [], finished: [:], dismissed: dismissed, now: now,
            timeZone: TimeZone(identifier: "UTC")!)
    }

    func testADismissedSessionLeavesTheEndedList() {
        let sessions = [ended("a", ago: 60), ended("b", ago: 120), ended("c", ago: 180)]
        var dismissals = EndedDismissals.none
        dismissals.dismiss(sessions[1])
        XCTAssertEqual(focus(sessions, .none).ended.map(\.session.session.sessionId), ["a", "b", "c"])
        let shown = focus(sessions, dismissals).ended
        XCTAssertEqual(shown.map(\.session.session.sessionId), ["a", "c"])
        XCTAssertEqual(shown.count, 2, "the home's Ended fold counts the same list")
    }

    func testDismissingEveryEndedSessionEmptiesTheFold() {
        let sessions = [ended("a"), ended("b", machine: "m2")]
        var dismissals = EndedDismissals.none
        sessions.forEach { dismissals.dismiss($0) }
        XCTAssertTrue(focus(sessions, dismissals).ended.isEmpty)
    }

    func testADismissedSessionThatResumedShowsInItsGroup() {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s", ago: 3600))
        let resumed = MachineSession(
            machineID: "m1", machineName: "m1", online: true,
            session: agentSession("s", state: .working, stateSinceMs: ms(ago: 30)))
        let result = focus([resumed], dismissals)
        XCTAssertEqual(result.running.map(\.session.session.sessionId), ["s"])
        XCTAssertTrue(result.ended.isEmpty)
    }

    func testADismissedSessionThatEndedAgainShowsAgain() {
        var dismissals = EndedDismissals.none
        dismissals.dismiss(ended("s", ago: 7200))
        XCTAssertEqual(focus([ended("s", ago: 7200)], dismissals).ended.count, 0)
        XCTAssertEqual(focus([ended("s", ago: 120)], dismissals).ended.map(\.session.session.sessionId), ["s"])
    }

    func testNamesAreWorkedOutOverWhatIsShown() {
        var a = agentSession("a", state: .ended, stateSinceMs: ms(ago: 60))
        a.title = "Fix bug"
        var b = agentSession("b", state: .ended, stateSinceMs: ms(ago: 120))
        b.title = "Fix bug"
        let sessions = [
            MachineSession(machineID: "m1", machineName: "m1", online: true, session: a),
            MachineSession(machineID: "m1", machineName: "m1", online: true, session: b),
        ]
        var dismissals = EndedDismissals.none
        dismissals.dismiss(sessions[0])
        XCTAssertEqual(focus(sessions, .none).ended.map(\.name), ["Fix bug", "Fix bug · #2"])
        XCTAssertEqual(focus(sessions, dismissals).ended.map(\.name), ["Fix bug"])
    }

    // MARK: - The store

    func testTheStoreStartsEmpty() throws {
        XCTAssertEqual(makeStore(try defaults()).dismissals, .none)
    }

    func testADismissalSurvivesALaunch() throws {
        let defaults = try defaults()
        let first = makeStore(defaults)
        first.dismiss(ended("s"))
        XCTAssertTrue(first.dismissals.hides(ended("s")))

        let relaunched = makeStore(defaults, at: 3600)
        XCTAssertTrue(relaunched.dismissals.hides(ended("s")))
        XCTAssertFalse(relaunched.dismissals.hides(ended("t")))
    }

    func testALaunchAfterTheTwelveHoursForgetsIt() throws {
        let defaults = try defaults()
        makeStore(defaults).dismiss(ended("s", ago: 600))
        XCTAssertTrue(makeStore(defaults, at: 43_199 - 600).dismissals.hides(ended("s", ago: 600)))

        let later = makeStore(defaults, at: 43_200)
        XCTAssertEqual(later.dismissals, .none)
        // Saved pruned: the entry is gone for good, not only hidden by the clock.
        let earlier = makeStore(defaults)
        XCTAssertFalse(earlier.dismissals.hides(ended("s", ago: 600)))
    }

    func testDismissingForgetsTheOldOnes() throws {
        let defaults = try defaults()
        let store = makeStore(defaults)
        store.dismiss(ended("old", ago: 43_000))
        let hour = makeStore(defaults, at: 1800)
        hour.dismiss(ended("new", ago: 60))
        XCTAssertFalse(hour.dismissals.hides(ended("old", ago: 43_000)))
        XCTAssertTrue(hour.dismissals.hides(ended("new", ago: 60)))
    }

    func testUnreadableSavedDataStartsEmpty() throws {
        let defaults = try defaults()
        defaults.set(Data("not json".utf8), forKey: EndedDismissalStore.key)
        let store = makeStore(defaults)
        XCTAssertEqual(store.dismissals, .none)
        store.dismiss(ended("s"))
        XCTAssertTrue(makeStore(defaults).dismissals.hides(ended("s")))
    }
}
