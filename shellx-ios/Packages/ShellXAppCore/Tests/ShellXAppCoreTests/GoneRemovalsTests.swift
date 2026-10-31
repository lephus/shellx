import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The sessions gone from their Mac that the user removed from this phone: a removal hides a session
/// only while its Mac reports exactly what it reported then, every home group and count leaves it out,
/// the removals survive a launch for 30 days, and only a session the phone saw answered `not_found`
/// this run swipes to be removed.
@MainActor
final class GoneRemovalsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var nowMs: Int64 { Int64(now.timeIntervalSince1970 * 1000) }
    private let day: TimeInterval = 86_400

    private func ms(ago seconds: Double) -> Int64 { nowMs - Int64(seconds * 1000) }

    /// A session as its Mac reports it: by default one that has said "working" for 52 hours.
    private func ghost(
        _ id: String = "s", machine: String = "m1", state: AgentState = .working,
        since: Double = 52 * 3600, activity: Double = 52 * 3600, workspace: String = "shellx"
    ) -> MachineSession {
        MachineSession(
            machineID: machine, machineName: machine, online: true,
            session: agentSession(
                id, state: state, lastActivityMs: ms(ago: activity), stateSinceMs: ms(ago: since), workspace: workspace))
    }

    private func removing(_ sessions: MachineSession..., at date: Date? = nil) -> GoneRemovals {
        var removals = GoneRemovals.none
        for session in sessions { removals.remove(session, at: date ?? now) }
        return removals
    }

    private func defaults() throws -> UserDefaults {
        let suite = "GoneRemovalsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return defaults
    }

    /// A store over `defaults` whose clock stands `offset` seconds after `now`.
    private func makeStore(_ defaults: UserDefaults, at offset: TimeInterval = 0) -> GoneRemovalStore {
        let clock = now.addingTimeInterval(offset)
        return GoneRemovalStore(defaults: defaults, now: { clock })
    }

    // MARK: - The value

    func testNothingIsHiddenUntilItIsRemoved() {
        XCTAssertFalse(GoneRemovals.none.hides(ghost()))
        XCTAssertTrue(removing(ghost()).hides(ghost()))
    }

    func testARemovalHidesOnlyWhatTheMacReportedThen() {
        let removals = removing(ghost())
        XCTAssertTrue(removals.hides(ghost()), "the same state, since and last activity")
        XCTAssertFalse(removals.hides(ghost(activity: 60)), "a newer last activity shows it again")
        XCTAssertFalse(removals.hides(ghost(since: 3600)), "another time it entered its state shows it again")
        XCTAssertFalse(removals.hides(ghost(state: .idle)), "another state shows it again")
        XCTAssertFalse(removals.hides(ghost(state: .ended)), "an end shows it again")
    }

    func testAStampWithoutTimesMatchesOnlyWithoutTimes() {
        let bare = MachineSession(
            machineID: "m1", machineName: "m1", online: true,
            session: agentSession("s", state: .working, lastActivityMs: nil, stateSinceMs: nil))
        let removals = removing(bare)
        XCTAssertTrue(removals.hides(bare))
        XCTAssertFalse(removals.hides(ghost()), "times the Mac gives later are a change")
    }

    func testARemovalIsPerMacAndPerSession() {
        let removals = removing(ghost("s", machine: "m1"))
        XCTAssertFalse(removals.hides(ghost("s", machine: "m2")), "the same id on another Mac is another session")
        XCTAssertFalse(removals.hides(ghost("other", machine: "m1")))
    }

    func testRemovingAgainKeepsTheNewStamp() {
        let removals = removing(ghost(activity: 3600), ghost(activity: 60))
        XCTAssertTrue(removals.hides(ghost(activity: 60)))
        XCTAssertFalse(removals.hides(ghost(activity: 3600)))
    }

    func testTheSharedFilterKeepsTheOrderAndDropsOnlyWhatIsHidden() {
        let sessions = [ghost("a"), ghost("b"), ghost("c"), ghost("b", machine: "m2")]
        let removals = removing(sessions[1])
        XCTAssertEqual(removals.shown(sessions), [sessions[0], sessions[2], sessions[3]])
        XCTAssertEqual(GoneRemovals.none.shown(sessions), sessions)
    }

    func testPruningDropsRemovalsThirtyDaysOld() {
        var removals = GoneRemovals.none
        removals.remove(ghost("old"), at: now.addingTimeInterval(-30 * day - 1))
        removals.remove(ghost("edge"), at: now.addingTimeInterval(-30 * day))
        removals.remove(ghost("fresh"), at: now.addingTimeInterval(-30 * day + 1))
        let pruned = removals.pruned(now: now)
        XCTAssertFalse(pruned.hides(ghost("old")))
        XCTAssertFalse(pruned.hides(ghost("edge")))
        XCTAssertTrue(pruned.hides(ghost("fresh")))
        var onlyFresh = GoneRemovals.none
        onlyFresh.remove(ghost("fresh"), at: now.addingTimeInterval(-30 * day + 1))
        XCTAssertEqual(pruned, onlyFresh, "a Mac with nothing left is not kept either")
    }

    func testARemovalAheadOfTheClockIsKept() {
        // The phone's clock was set back after the removal.
        let removals = removing(ghost(), at: now.addingTimeInterval(3600))
        XCTAssertTrue(removals.pruned(now: now).hides(ghost()))
    }

    func testItSurvivesEncoding() throws {
        var removals = GoneRemovals.none
        removals.remove(ghost("s", machine: "m1"), at: now)
        removals.remove(ghost("t", machine: "m2", state: .needsInput, since: 90), at: now.addingTimeInterval(-60))
        removals.remove(ghost("u", state: .other("compacting")), at: now)
        let back = try JSONDecoder().decode(GoneRemovals.self, from: JSONEncoder().encode(removals))
        XCTAssertEqual(back, removals)
        XCTAssertTrue(back.hides(ghost("s", machine: "m1")))
        XCTAssertTrue(back.hides(ghost("t", machine: "m2", state: .needsInput, since: 90)))
        XCTAssertTrue(back.hides(ghost("u", state: .other("compacting"))))
    }

    // MARK: - Every home group and its count

    private func focus(
        _ sessions: [MachineSession], removed: GoneRemovals, pending: [MachinePendingItem] = [],
        finished: [String: [String: Date]] = [:]
    ) -> HomeFocus {
        HomeFocus.make(
            sessions: sessions, pending: pending, finished: finished, removed: removed, now: now,
            timeZone: TimeZone(identifier: "UTC")!)
    }

    private func ids(_ items: [FocusItem]) -> [String] { items.map(\.session.session.sessionId) }

    func testARemovedSessionLeavesEveryHomeGroupAndItsCount() {
        let waiting = ghost("n", state: .needsInput, since: 600, activity: 600)
        let running = ghost("r")
        let live = ghost("live", since: 60, activity: 5)
        let done = ghost("d", state: .idle, since: 300, activity: 300)
        let ended = ghost("e", state: .ended, since: 3600, activity: 3600)
        let sessions = [waiting, running, live, done, ended]
        let finished = ["m1": ["d": now.addingTimeInterval(-300)]]

        let before = focus(sessions, removed: .none, finished: finished)
        XCTAssertEqual(ids(before.needsYou), ["n"])
        XCTAssertEqual(ids(before.running), ["live", "r"])
        XCTAssertEqual(ids(before.justDone), ["d"])
        XCTAssertEqual(ids(before.ended), ["e"])

        let after = focus(sessions, removed: removing(waiting, running, done, ended), finished: finished)
        XCTAssertEqual(ids(after.needsYou), [])
        XCTAssertEqual(ids(after.running), ["live"])
        XCTAssertEqual(after.running.count, 1, "\"Running · N\" counts the same list")
        XCTAssertEqual(ids(after.justDone), [])
        XCTAssertEqual(ids(after.ended), [], "the Ended fold and its page leave it out too")
    }

    func testARequestDoesNotBringARemovedSessionBackAsNeedsYou() {
        // The Mac lists a request of the removed session's workspace and agent: it goes to another session
        // of that workspace, or to none.
        let removedOne = ghost("r", workspace: "web")
        let request = MachinePendingItem(
            machineID: "m1", machineName: "m1", item: pendingItem("p1", workspace: "web"), actionable: true)
        XCTAssertEqual(ids(focus([removedOne], removed: .none, pending: [request]).needsYou), ["r"])
        XCTAssertTrue(focus([removedOne], removed: removing(removedOne), pending: [request]).isQuiet)

        let other = ghost("w", since: 600, activity: 600, workspace: "web")
        let shown = focus([removedOne, other], removed: removing(removedOne), pending: [request])
        XCTAssertEqual(ids(shown.needsYou), ["w"])
        XCTAssertEqual(ids(shown.running), [])
    }

    func testARemovedSessionShowsAgainWhenItsMacReportsAChange() {
        let removals = removing(ghost("r"))
        XCTAssertEqual(ids(focus([ghost("r")], removed: removals).running), [])
        XCTAssertEqual(ids(focus([ghost("r", activity: 30)], removed: removals).running), ["r"])
        XCTAssertEqual(ids(focus([ghost("r", state: .needsInput, since: 30)], removed: removals).needsYou), ["r"])
    }

    func testNamesAreWorkedOutOverWhatIsShown() {
        var a = agentSession("a", lastActivityMs: ms(ago: 60), stateSinceMs: ms(ago: 60))
        a.title = "Fix bug"
        var b = agentSession("b", lastActivityMs: ms(ago: 120), stateSinceMs: ms(ago: 120))
        b.title = "Fix bug"
        let sessions = [
            MachineSession(machineID: "m1", machineName: "m1", online: true, session: a),
            MachineSession(machineID: "m1", machineName: "m1", online: true, session: b),
        ]
        XCTAssertEqual(focus(sessions, removed: .none).running.map(\.name), ["Fix bug", "Fix bug · #2"])
        XCTAssertEqual(focus(sessions, removed: removing(sessions[0])).running.map(\.name), ["Fix bug"])
    }

    // MARK: - The store

    func testTheStoreStartsEmpty() throws {
        XCTAssertEqual(makeStore(try defaults()).removals, .none)
    }

    func testARemovalSurvivesALaunch() throws {
        let defaults = try defaults()
        let first = makeStore(defaults)
        first.remove(ghost())
        XCTAssertTrue(first.removals.hides(ghost()))

        let relaunched = makeStore(defaults, at: 7 * day)
        XCTAssertTrue(relaunched.removals.hides(ghost()))
        XCTAssertFalse(relaunched.removals.hides(ghost("t")))
    }

    func testALaunchThirtyDaysLaterForgetsIt() throws {
        let defaults = try defaults()
        makeStore(defaults).remove(ghost())
        XCTAssertTrue(makeStore(defaults, at: 30 * day - 1).removals.hides(ghost()))

        XCTAssertEqual(makeStore(defaults, at: 30 * day).removals, .none)
        // Saved pruned: the removal is gone for good, not only hidden by the clock.
        XCTAssertFalse(makeStore(defaults).removals.hides(ghost()))
    }

    func testRemovingForgetsTheOldOnes() throws {
        let defaults = try defaults()
        makeStore(defaults).remove(ghost("old"))
        let later = makeStore(defaults, at: 30 * day - 60)
        XCTAssertTrue(later.removals.hides(ghost("old")))
        let laterStill = makeStore(defaults, at: 30 * day + 60)
        laterStill.remove(ghost("new"))
        XCTAssertFalse(laterStill.removals.hides(ghost("old")))
        XCTAssertTrue(laterStill.removals.hides(ghost("new")))
    }

    func testUnreadableSavedDataStartsEmpty() throws {
        let defaults = try defaults()
        defaults.set(Data("not json".utf8), forKey: GoneRemovalStore.key)
        let store = makeStore(defaults)
        XCTAssertEqual(store.removals, .none)
        store.remove(ghost())
        XCTAssertTrue(makeStore(defaults).removals.hides(ghost()))
    }

    func testItKeepsItsOwnKey() throws {
        XCTAssertEqual(GoneRemovalStore.key, "shellx.removedGone")
        XCTAssertNotEqual(GoneRemovalStore.key, EndedDismissalStore.key)
    }

    // MARK: - Known gone this run

    func testOnlyASessionSeenGoneThisRunSwipesToBeRemoved() throws {
        let defaults = try defaults()
        let store = makeStore(defaults)
        let gone = ghost("gone")
        let live = ghost("live", since: 60, activity: 5)
        XCTAssertFalse(store.canRemove(gone), "nothing is known gone before an agent screen hears not_found")
        XCTAssertEqual(store.removable([gone, live]), [])

        store.noteGone(gone)
        XCTAssertTrue(store.canRemove(gone))
        XCTAssertFalse(store.canRemove(live), "a live session never gets it")
        XCTAssertEqual(store.removable([gone, live]), [gone.ref])
        XCTAssertFalse(store.canRemove(ghost("gone", machine: "m2")), "the same id on another Mac")
        XCTAssertFalse(
            store.canRemove(ghost("gone", activity: 30)), "the Mac reported a change since it was seen gone")

        XCTAssertFalse(makeStore(defaults).canRemove(gone), "known gone is this run's only")
    }

    func testRemovingHidesItAndKeepsWhatIsKnown() throws {
        let store = makeStore(try defaults())
        let gone = ghost("gone")
        store.noteGone(gone)
        store.remove(gone)
        XCTAssertTrue(store.removals.hides(gone))
        XCTAssertEqual(store.removals.shown([gone, ghost("other")]).map(\.session.sessionId), ["other"])
    }
}
