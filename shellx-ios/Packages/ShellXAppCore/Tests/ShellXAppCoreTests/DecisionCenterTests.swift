import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import ShellXLinkSession
import XCTest

@testable import ShellXAppCore

/// Sending a decision from a card: what the card shows meanwhile and after, against a real hub and
/// `FakeMac` (A1: a handled item disappears; a tap that cannot be sent says so).
@MainActor
final class DecisionCenterTests: XCTestCase {
    func testDeliveredHidesCardBeforeResolvedArrives() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(permissionItem("r1"))
        await mac.addPending(permissionItem("r2"))
        // The Mac answers `delivered` but its `agent.changed` comes later.
        await mac.setReplyOutcome(.delivered, resolves: false)
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 2)
        XCTAssertTrue(synced)
        let key = rig.key(mac, "r1")

        await rig.center.send(.permission(.once), for: key)

        XCTAssertEqual(rig.center.status[key], .done)
        XCTAssertEqual(rig.hub.pendingItems.map(\.item.requestId), ["r1", "r2"], "the Mac has not resolved it yet")
        XCTAssertEqual(rig.visibleIDs, ["r2"], "the card goes at once")
        let decisions = await mac.decisions
        XCTAssertEqual(decisions, [FakeMac.Decision(requestId: "r1", decision: .permission(.once))])
        XCTAssertEqual(rig.latency.summary(.replyRoundTrip)?.count, 1, "tap to delivered is measured once")

        await mac.resolvePending("r1")
        let gone = await eventually { rig.hub.pendingItems.count == 1 }
        XCTAssertTrue(gone)
        XCTAssertEqual(rig.visibleIDs, ["r2"])
        XCTAssertNil(rig.center.status[key])
    }

    func testAlreadyHandledShowsThenHides() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(permissionItem("r1"))
        await mac.setReplyOutcome(.alreadyHandled)
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let key = rig.key(mac, "r1")

        await rig.center.send(.permission(.once), for: key)

        XCTAssertEqual(rig.center.status[key], .handledElsewhere)
        XCTAssertEqual(rig.visibleIDs, ["r1"], "the card stays to say so")
        let lingering = await eventually { rig.linger.waiting == [DecisionCenter.handledElsewhereLinger] }
        XCTAssertTrue(lingering, "\(rig.linger.waiting)")
        XCTAssertEqual(DecisionCenter.handledElsewhereLinger, .seconds(2))
        XCTAssertEqual(rig.visibleIDs, ["r1"], "still there while the linger runs")
        XCTAssertNil(rig.latency.summary(.replyRoundTrip), "nothing reached the agent")

        await rig.center.send(.permission(.deny), for: key)
        let decisions = await mac.decisions
        XCTAssertEqual(decisions.count, 1, "a handled item takes no other decision")

        rig.linger.release()
        let hidden = await eventually { rig.visibleIDs.isEmpty }
        XCTAssertTrue(hidden)
    }

    func testHandledElsewhereLingersAfterItemLeaves() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(permissionItem("r1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        XCTAssertEqual(rig.visibleIDs, ["r1"], "the card is on screen")
        let key = rig.key(mac, "r1")
        // Decided on the Mac before the tap arrives: the item leaves while the reply is on its way.
        await mac.resolvePending("r1")
        let left = await eventually { rig.hub.pendingItems.isEmpty }
        XCTAssertTrue(left)

        await rig.center.send(.permission(.once), for: key)

        XCTAssertEqual(rig.center.status[key], .handledElsewhere)
        let shown = rig.shown
        XCTAssertEqual(shown.map(\.item.requestId), ["r1"], "the card says it was handled elsewhere")
        XCTAssertEqual(shown.map(\.actionable), [false])
        let lingering = await eventually { rig.linger.waiting.count == 1 }
        XCTAssertTrue(lingering)
        rig.linger.release()
        let hidden = await eventually { rig.visibleIDs.isEmpty }
        XCTAssertTrue(hidden)
        XCTAssertNil(rig.center.status[key])
    }

    func testUnknownKeepsCardWithRejected() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(permissionItem("r1"))
        await mac.setReplyOutcome(.unknown)
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let key = rig.key(mac, "r1")

        await rig.center.send(.permission(.always), for: key)

        XCTAssertEqual(rig.center.status[key], .failed(.rejected))
        XCTAssertEqual(rig.visibleIDs, ["r1"])

        // A host error answering the call reads the same.
        let sender = ScriptedSender([.failure(LinkClientError.remote(code: "bad_request", message: "no"))])
        let center = DecisionCenter(sender: sender, latency: LatencyLog(), sleep: rig.linger.sleep)
        await center.send(.permission(.once), for: key)
        XCTAssertEqual(center.status[key], .failed(.rejected))
        let other = ScriptedSender([.outcome(.other("later"))])
        let center2 = DecisionCenter(sender: other, latency: LatencyLog(), sleep: rig.linger.sleep)
        await center2.send(.permission(.once), for: key)
        XCTAssertEqual(center2.status[key], .failed(.rejected))
    }

    func testTimeoutResendsOnceThenFails() async {
        let key = PendingKey(machineID: "m1", requestId: "r1")
        let sender = ScriptedSender([.failure(LinkClientError.timedOut)])
        let latency = LatencyLog()
        let center = DecisionCenter(sender: sender, latency: latency, sleep: ManualSleeper().sleep)

        await center.send(.permission(.once), for: key)

        XCTAssertEqual(sender.calls.count, 2, "one resend, which is safe: replies are idempotent")
        XCTAssertEqual(sender.calls.map(\.decision), [.permission(.once), .permission(.once)])
        XCTAssertEqual(center.status[key], .failed(.noAnswer))

        // "Try again" sends the same decision again.
        await center.retry(key)
        XCTAssertEqual(sender.calls.count, 4)

        let second = PendingKey(machineID: "m1", requestId: "r2")
        let flaky = ScriptedSender([.failure(LinkClientError.timedOut), .outcome(.delivered)])
        let center2 = DecisionCenter(sender: flaky, latency: latency, sleep: ManualSleeper().sleep)
        await center2.send(.permission(.deny), for: second)
        XCTAssertEqual(flaky.calls.count, 2)
        XCTAssertEqual(center2.status[second], .done)
        XCTAssertEqual(latency.summary(.replyRoundTrip)?.count, 1, "the round trip spans both tries")
    }

    func testSecondTapWhileSendingIgnored() async {
        let key = PendingKey(machineID: "m1", requestId: "r1")
        let gate = Gate()
        let sender = ScriptedSender([.outcome(.delivered)])
        sender.gate = gate
        let center = DecisionCenter(sender: sender, latency: LatencyLog(), sleep: ManualSleeper().sleep)

        let first = Task { await center.send(.permission(.once), for: key) }
        let held = await eventually { gate.waiting == 1 }
        XCTAssertTrue(held)
        XCTAssertEqual(center.status[key], .sending)

        await center.send(.permission(.deny), for: key)
        await center.retry(key)
        XCTAssertEqual(sender.calls.count, 1, "taps while sending do nothing")
        XCTAssertEqual(center.status[key], .sending)

        gate.open()
        await first.value
        XCTAssertEqual(center.status[key], .done)
        await center.send(.permission(.deny), for: key)
        XCTAssertEqual(sender.calls.count, 1, "nor taps after it was delivered")
    }

    func testOfflineFailsWithoutResend() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(permissionItem("r1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let key = rig.key(mac, "r1")
        // The network goes: the session drops and the next attempt fails, so the Mac is offline.
        await mac.failNextConnects(URLError(.notConnectedToInternet), count: 1)
        await mac.dropLiveSessions()
        let reconnecting = await eventually { rig.backoff.waiting.count == 1 }
        XCTAssertTrue(reconnecting, "\(rig.hub.machines.map(\.state))")
        rig.backoff.release()
        let offline = await eventually {
            guard case .offline = rig.hub.machines.first?.state else { return false }
            return rig.backoff.waiting.count == 1
        }
        XCTAssertTrue(offline, "\(rig.hub.machines.map(\.state))")

        await rig.center.send(.permission(.once), for: key)

        XCTAssertEqual(rig.center.status[key], .failed(.offline))
        // Back online: nothing was queued, so nothing goes out by itself (spec section 7.5).
        rig.backoff.release()
        let back = await rig.synced(count: 1)
        XCTAssertTrue(back)
        let decisions = await mac.decisions
        XCTAssertEqual(decisions, [])
        XCTAssertEqual(rig.center.status[key], .failed(.offline))
        // The card is back with live buttons: "offline, not sent" no longer holds.
        rig.center.sync(rig.hub.pendingItems)
        XCTAssertNil(rig.center.status[key])
        let after = await mac.decisions
        XCTAssertEqual(after, [], "clearing the message sends nothing")

        // A session that ends while the reply is out reads the same, and is not resent.
        let sender = ScriptedSender([.failure(LinkClientError.sessionClosed)])
        let center = DecisionCenter(sender: sender, latency: LatencyLog(), sleep: rig.linger.sleep)
        await center.send(.permission(.once), for: key)
        XCTAssertEqual(center.status[key], .failed(.offline))
        XCTAssertEqual(sender.calls.count, 1)
    }

    func testTapWhileReconnectingFailsVisibly() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(permissionItem("r1"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        XCTAssertEqual(rig.shown.map(\.actionable), [true])
        let key = rig.key(mac, "r1")
        // The session drops; the next one connects but has not synced yet.
        await mac.holdSnapshots()
        await mac.dropLiveSessions()
        let reconnecting = await eventually { rig.backoff.waiting.count == 1 }
        XCTAssertTrue(reconnecting, "\(rig.hub.machines.map(\.state))")
        XCTAssertEqual(rig.shown.map(\.actionable), [false])
        rig.backoff.release()
        let unsynced = await eventually {
            let held = await mac.heldSnapshotCount
            return held == 1 && rig.hub.pendingItems.map(\.actionable) == [false]
        }
        XCTAssertTrue(unsynced, "\(rig.hub.machines.map(\.state))")
        XCTAssertEqual(rig.shown.map(\.actionable), [false], "buttons off")

        // A tap that got through anyway (it raced the redraw) fails where the user can see it.
        await rig.center.send(.permission(.once), for: key)

        XCTAssertEqual(rig.center.status[key], .failed(.offline))
        let decisions = await mac.decisions
        XCTAssertEqual(decisions, [], "nothing was sent for unsynced data")

        rig.center.sync(rig.hub.pendingItems)
        XCTAssertEqual(rig.center.status[key], .failed(.offline), "still not live: the card keeps saying so")

        await mac.releaseSnapshots()
        let back = await rig.synced(count: 1)
        XCTAssertTrue(back)
        XCTAssertEqual(rig.shown.map(\.actionable), [true])
        XCTAssertNil(rig.center.status[key], "live again: the offline note goes, the buttons are back")
        let still = await mac.decisions
        XCTAssertEqual(still, [], "and nothing goes out once it syncs")
    }

    func testVisibleItemsOnlyReads() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(permissionItem("r1"))
        await mac.setReplyOutcome(.unknown)
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 1)
        XCTAssertTrue(synced)
        let key = rig.key(mac, "r1")
        await rig.center.send(.permission(.once), for: key)
        await mac.resolvePending("r1")
        let gone = await eventually { rig.hub.pendingItems.isEmpty }
        XCTAssertTrue(gone)

        // A body may call it any number of times, with any subset: nothing changes.
        XCTAssertEqual(rig.center.visibleItems([]), [])
        XCTAssertEqual(rig.center.status[key], .failed(.rejected))

        rig.center.sync(rig.hub.pendingItems)
        XCTAssertNil(rig.center.status[key], "sync forgets what left the set")
    }

    func testResolvedItemClearsStatus() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(permissionItem("r1"))
        await mac.addPending(permissionItem("r2"))
        await mac.setReplyOutcome(.unknown)
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 2)
        XCTAssertTrue(synced)
        let key = rig.key(mac, "r1")
        await rig.center.send(.permission(.once), for: key)
        XCTAssertEqual(rig.center.status[key], .failed(.rejected))

        await mac.resolvePending("r1")
        let gone = await eventually { rig.hub.pendingItems.count == 1 }
        XCTAssertTrue(gone)

        XCTAssertEqual(rig.visibleIDs, ["r2"])
        XCTAssertNil(rig.center.status[key], "a resolved item's status is forgotten")
        XCTAssertTrue(rig.center.status.isEmpty)
    }

    func testFeedbackOver4096BytesRefused() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(planItem("p1"))
        await mac.addPending(planItem("p2"))
        let rig = try await PendingRig.make([mac], in: self)
        let synced = await rig.synced(count: 2)
        XCTAssertTrue(synced)
        XCTAssertEqual(DecisionCenter.maxFeedbackBytes, 4096)
        // "ệ" is 3 bytes: 1366 of them are 4098 bytes.
        let tooLong = String(repeating: "ệ", count: 1366)

        await rig.center.send(.exitPlan(.deny, feedback: tooLong), for: rig.key(mac, "p1"))

        XCTAssertNil(rig.center.status[rig.key(mac, "p1")], "refused before anything is sent")
        var decisions = await mac.decisions
        XCTAssertEqual(decisions, [])

        let fits = String(repeating: "ệ", count: 1365) + "a"
        XCTAssertEqual(fits.utf8.count, 4096)
        await rig.center.send(.exitPlan(.deny, feedback: fits), for: rig.key(mac, "p2"))
        XCTAssertEqual(rig.center.status[rig.key(mac, "p2")], .done)
        decisions = await mac.decisions
        XCTAssertEqual(decisions.map(\.requestId), ["p2"])
    }
}
