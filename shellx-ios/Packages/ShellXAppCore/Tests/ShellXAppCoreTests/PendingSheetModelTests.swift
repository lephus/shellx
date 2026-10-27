import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The question and plan sheets stay open while the user reads: the item may be decided elsewhere
/// meanwhile (Review Focus 2).
@MainActor
final class PendingSheetModelTests: XCTestCase {
    func testSheetReportsHandledElsewhereWhenItemResolved() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(questionItem("q1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let sheet = PendingSheetModel(key: rig.key(mac, "q1"), hub: rig.hub, center: rig.center)
        XCTAssertEqual(sheet.opened?.item.requestId, "q1")
        XCTAssertTrue(sheet.canSend)
        XCTAssertFalse(sheet.handledElsewhere)

        // Answered on the Mac while the sheet is open.
        await mac.resolvePending("q1")
        let flagged = await eventually { sheet.handledElsewhere }

        XCTAssertTrue(flagged)
        XCTAssertFalse(sheet.canSend)
        XCTAssertEqual(sheet.opened?.item.requestId, "q1", "the sheet keeps showing what was asked")
        await sheet.send(.question(selections: ["Postgres"]))
        let decisions = await mac.decisions
        XCTAssertEqual(decisions, [], "the sheet sends nothing")
    }

    func testSheetNotFlaggedAfterOwnSend() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(questionItem("q1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let key = rig.key(mac, "q1")
        let sheet = PendingSheetModel(key: key, hub: rig.hub, center: rig.center)

        await sheet.send(.question(selections: ["Free text answer"]))

        XCTAssertEqual(sheet.status, .done)
        let decisions = await mac.decisions
        XCTAssertEqual(decisions, [FakeMac.Decision(requestId: "q1", decision: .question(selections: ["Free text answer"]))])
        let gone = await eventually { rig.hub.pendingItems.isEmpty }
        XCTAssertTrue(gone, "the Mac resolved it")
        rig.center.sync(rig.hub.pendingItems)
        XCTAssertNil(rig.center.status[key], "the center forgot it")
        XCTAssertFalse(sheet.handledElsewhere, "our own answer is not someone else's")
        XCTAssertEqual(sheet.status, .done)
        XCTAssertFalse(sheet.canSend)
    }

    func testSheetWaitsWhileReconnecting() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(planItem("p1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let sheet = PendingSheetModel(key: rig.key(mac, "p1"), hub: rig.hub, center: rig.center)
        XCTAssertTrue(sheet.actionable)

        await mac.dropLiveSessions()
        let waiting = await eventually { !sheet.actionable }

        XCTAssertTrue(waiting)
        XCTAssertFalse(sheet.canSend)
        XCTAssertFalse(sheet.handledElsewhere, "still pending, just not synced")
    }

    // MARK: - The Mac goes away while the sheet is open (final review, Important 1)

    /// Ends the Mac's session and lets the first reconnect fail: the Mac is offline, its items gone.
    private func dropAndFailReconnect(_ mac: FakeMac, _ rig: PendingRig) async -> Bool {
        await mac.failNextConnects(URLError(.notConnectedToInternet), count: 1)
        await mac.dropLiveSessions()
        guard await eventually({ rig.backoff.waiting.count == 1 }) else { return false }
        rig.backoff.release()
        return await eventually {
            guard case .offline = rig.hub.machines.first?.state else { return false }
            return rig.hub.pendingItems.isEmpty && rig.backoff.waiting.count == 1
        }
    }

    func testSheetWaitsWhileTheMacIsOfflineThenSendsWhenItIsBack() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(questionItem("q1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let sheet = PendingSheetModel(key: rig.key(mac, "q1"), hub: rig.hub, center: rig.center)

        let offline = await dropAndFailReconnect(mac, rig)
        XCTAssertTrue(offline, "the failed reconnect dropped the item")

        XCTAssertFalse(sheet.handledElsewhere, "the Mac went offline; nobody handled the question")
        XCTAssertFalse(sheet.canSend)
        XCTAssertEqual(sheet.linkNote, .offline)
        XCTAssertEqual(sheet.opened?.item.requestId, "q1", "the sheet keeps what was asked")
        await sheet.send(.question(selections: ["Postgres"]))
        var decisions = await mac.decisions
        XCTAssertEqual(decisions, [], "nothing is sent while the Mac is offline")

        // The Mac is back and the question still waits: the answer typed meanwhile can go.
        rig.backoff.release()
        let back = await eventually { sheet.canSend }
        XCTAssertTrue(back)
        XCTAssertFalse(sheet.handledElsewhere)
        XCTAssertNil(sheet.linkNote)
        await sheet.send(.question(selections: ["Postgres"]))
        XCTAssertEqual(sheet.status, .done)
        decisions = await mac.decisions
        XCTAssertEqual(decisions, [FakeMac.Decision(requestId: "q1", decision: .question(selections: ["Postgres"]))])
    }

    func testItemResolvedWhileTheMacWasOfflineIsHandledOnceSyncedAgain() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(questionItem("q1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let sheet = PendingSheetModel(key: rig.key(mac, "q1"), hub: rig.hub, center: rig.center)
        let offline = await dropAndFailReconnect(mac, rig)
        XCTAssertTrue(offline)
        XCTAssertFalse(sheet.handledElsewhere)

        // Answered on the Mac while this iPhone could not see it; the next sync no longer lists it.
        await mac.resolvePending("q1")
        rig.backoff.release()
        let online = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(online)
        let handled = await eventually { sheet.handledElsewhere }
        XCTAssertTrue(handled)
        XCTAssertFalse(sheet.canSend)
        XCTAssertNil(sheet.linkNote)
    }

    func testHandledWhileOnlineStaysHandledWhenTheMacThenGoesOffline() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(questionItem("q1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let sheet = PendingSheetModel(key: rig.key(mac, "q1"), hub: rig.hub, center: rig.center)
        await mac.resolvePending("q1")
        let flagged = await eventually { sheet.handledElsewhere }
        XCTAssertTrue(flagged)

        let offline = await dropAndFailReconnect(mac, rig)
        XCTAssertTrue(offline)

        XCTAssertTrue(sheet.handledElsewhere, "it left the list while the Mac was online and synced")
        XCTAssertFalse(sheet.canSend)
        XCTAssertNil(sheet.linkNote)
    }

    func testSheetWaitsWhenTheMacRemovesThisIPhone() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(planItem("p1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let sheet = PendingSheetModel(key: rig.key(mac, "p1"), hub: rig.hub, center: rig.center)

        // The Mac refuses this iPhone from now on: the next connect is not granted.
        await mac.failNextConnects(RelayAPIError.http(status: 403, code: "not_granted"), count: 5)
        await mac.dropLiveSessions()
        let retrying = await eventually { rig.backoff.waiting.count == 1 }
        XCTAssertTrue(retrying)
        rig.backoff.release()
        let revoked = await eventually { rig.hub.machines.first?.state == .revoked }
        XCTAssertTrue(revoked)
        XCTAssertEqual(rig.hub.pendingItems, [])

        XCTAssertFalse(sheet.handledElsewhere, "the Mac removed this iPhone; nobody handled the plan")
        XCTAssertFalse(sheet.canSend)
        XCTAssertEqual(sheet.linkNote, .needsPairing)
    }

    func testSheetWaitsWhenTheRelayNoLongerGrantsTheMac() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(questionItem("q1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let sheet = PendingSheetModel(key: rig.key(mac, "q1"), hub: rig.hub, center: rig.center)

        // The relay lists no grant for the Mac any more (the rig's relay has none).
        await rig.hub.refreshGrants()
        XCTAssertEqual(rig.hub.machines.first?.state, .revoked)
        XCTAssertEqual(rig.hub.pendingItems, [])

        XCTAssertFalse(sheet.handledElsewhere)
        XCTAssertFalse(sheet.canSend)
        XCTAssertEqual(sheet.linkNote, .needsPairing)
    }
}
