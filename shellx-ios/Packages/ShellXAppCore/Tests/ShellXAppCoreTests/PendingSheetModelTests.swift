import Foundation
import ShellXAppTestSupport
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
}
