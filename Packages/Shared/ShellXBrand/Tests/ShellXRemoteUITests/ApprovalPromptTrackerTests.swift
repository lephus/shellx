import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let delay = ApprovalPromptTracker.armingDelay

private func request(
    _ id: String,
    code: String = "482915",
    fingerprint: String = "8877665544332211",
    name: String? = nil,
    suspicious: Bool = false,
    firstSeen: Date = t0
) -> PairingRequest {
    PairingRequest(
        id: id, fromMachineID: "m-\(id)", requesterName: name ?? "Mac \(id)", code: code,
        fingerprint: fingerprint, suspicious: suspicious, firstSeen: firstSeen
    )
}

/// A tracker that has seen `queue` at `at`, like the controller's first refresh.
private func observed(_ queue: [PairingRequest], at: Date = t0) -> ApprovalPromptTracker {
    var tracker = ApprovalPromptTracker()
    tracker.observe(queue: queue, now: at)
    return tracker
}

private func armed(_ at: Date = t0) -> Date { at.addingTimeInterval(delay) }

@Suite struct ApprovalPromptTrackerTests {
    @Test func approvingTheShownRequestStartsAndThenHidesItEvenIfTheServiceStillListsIt() {
        let a = request("a")
        let b = request("b", firstSeen: t0.addingTimeInterval(5))
        let queue = [a, b]
        var tracker = observed(queue, at: t0.addingTimeInterval(10))
        let now = armed(t0.addingTimeInterval(10))
        let started = tracker.begin(.approve, request: a, queue: queue, now: now)
        #expect(started)
        #expect(tracker.model(queue: queue, now: now).isBusy)

        tracker.finish(.approve, requestID: "a", failureCode: nil)
        let model = tracker.model(queue: queue, now: now)
        #expect(!model.isBusy)
        // The service has not dropped "a" yet; the panel already moved on.
        #expect(model.current?.id == "b")
        #expect(model.queueText == nil)
    }

    @Test func suspiciousRequestIsNeverApprovedButCanBeDenied() {
        let a = request("a", suspicious: true)
        let queue = [a]
        var tracker = observed(queue)
        let began1 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(!began1)
        #expect(!tracker.model(queue: queue, now: armed()).isBusy)
        let began2 = tracker.begin(.deny, request: a, queue: queue, now: armed())
        #expect(began2)
    }

    @Test func aStaleButtonCannotActOnADifferentRequest() {
        // The person saw "a"; by the time the click lands "b" is on screen.
        let a = request("a")
        let b = request("b", firstSeen: t0.addingTimeInterval(100))
        let queue = [b]
        let at = t0.addingTimeInterval(310)
        var tracker = observed(queue, at: at)
        let now = armed(at)
        let began3 = tracker.begin(.approve, request: a, queue: queue, now: now)
        #expect(!began3)
        let began4 = tracker.begin(.deny, request: a, queue: queue, now: now)
        #expect(!began4)
        #expect(!tracker.model(queue: queue, now: now).isBusy)
    }

    @Test func aRequestThatIsNotTheOldestCannotBeActedOn() {
        let a = request("a")
        let b = request("b", firstSeen: t0.addingTimeInterval(5))
        let queue = [a, b]
        var tracker = observed(queue, at: t0.addingTimeInterval(10))
        let began5 = tracker.begin(.approve, request: b, queue: queue, now: armed(t0.addingTimeInterval(10)))
        #expect(!began5)
    }

    @Test func anExpiredRequestCannotBeApprovedOrDenied() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue)
        let began6 = tracker.begin(.approve, request: a, queue: queue, now: t0.addingTimeInterval(300))
        #expect(!began6)
        let began7 = tracker.begin(.deny, request: a, queue: queue, now: t0.addingTimeInterval(301))
        #expect(!began7)
    }

    @Test func onlyOneDecisionIsInFlightAtATime() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue)
        let began8 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(began8)
        let began9 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(!began9)
        let began10 = tracker.begin(.deny, request: a, queue: queue, now: armed())
        #expect(!began10)
    }

    @Test func aFailedApproveShowsInlineAndAllowsAnotherTry() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue)
        let began11 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(began11)
        tracker.finish(.approve, requestID: "a", failureCode: "network")

        let model = tracker.model(queue: queue, now: armed())
        #expect(model.current?.id == "a")
        #expect(model.errorText == "Can't reach relay.shellx.pro")
        #expect(!model.isBusy)
        #expect(model.canApprove)
        // A new attempt clears the old message while it runs.
        let began12 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(began12)
        #expect(tracker.model(queue: queue, now: armed()).errorText == nil)
    }

    @Test func aFingerprintMismatchFromTheServiceBlocksApprovingThatRequest() {
        let a = request("a")
        let b = request("b", firstSeen: t0.addingTimeInterval(5))
        let queue = [a, b]
        var tracker = observed(queue)
        let began13 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(began13)
        tracker.finish(.approve, requestID: "a", failureCode: "fingerprint_mismatch")

        let model = tracker.model(queue: queue, now: armed())
        #expect(model.warning == "The fingerprint does not match what the server reports. Do not approve.")
        #expect(!model.canApprove)
        let began14 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(!began14)
        let began15 = tracker.begin(.deny, request: a, queue: queue, now: armed())
        #expect(began15)
    }

    @Test func aFailureBelongsToItsRequestOnly() {
        let a = request("a")
        let b = request("b", firstSeen: t0.addingTimeInterval(5))
        var tracker = observed([a, b])
        let began16 = tracker.begin(.approve, request: a, queue: [a, b], now: armed())
        #expect(began16)
        tracker.finish(.approve, requestID: "a", failureCode: "network")
        // "a" is denied by someone else / gone; "b" is shown without a's error.
        let model = tracker.model(queue: [b], now: armed())
        #expect(model.current?.id == "b")
        #expect(model.errorText == nil)
    }

    @Test func decidedAndFailedRequestsAreForgottenOnceTheServiceDropsThem() {
        let a = request("a")
        var tracker = observed([a])
        let began17 = tracker.begin(.deny, request: a, queue: [a], now: armed())
        #expect(began17)
        tracker.finish(.deny, requestID: "a", failureCode: nil)
        #expect(tracker.model(queue: [a], now: armed()).current == nil)

        tracker.prune(queue: [])
        // A new request that reuses the id is a new request and shows again.
        #expect(tracker.model(queue: [a], now: armed()).current?.id == "a")
    }

    @Test func nothingStartsOnceStopped() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue)
        tracker.stop()
        #expect(tracker.isStopped)
        let began18 = tracker.begin(.deny, request: a, queue: queue, now: armed())
        #expect(!began18)
        let began19 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(!began19)
    }

    @Test func aResultAfterStopChangesNothingVisible() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue)
        let began20 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(began20)
        tracker.stop()
        tracker.finish(.approve, requestID: "a", failureCode: nil)
        // Stopped: no decision is recorded that could hide a request later.
        #expect(tracker.model(queue: queue, now: armed()).current?.id == "a")
    }

    @Test func aFinishForAnotherRequestIsIgnored() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue)
        let began21 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(began21)
        tracker.finish(.approve, requestID: "zzz", failureCode: nil)
        #expect(tracker.model(queue: queue, now: armed()).isBusy)
    }

    @Test func modelCarriesTheLabelsItIsGiven() {
        let tracker = ApprovalPromptTracker()
        let labels = ApprovalPromptLabels(
            title: "%@ wants in", compare: "c", suspicious: "s", approve: "Yes", deny: "No",
            queue: "%lld/%lld", network: "n", codeLabel: "Code", fingerprintLabel: "FP"
        )
        let queue = [request("a"), request("b", firstSeen: t0.addingTimeInterval(1))]
        let model = tracker.model(queue: queue, now: t0, labels: labels)
        #expect(model.title == "Mac a wants in")
        #expect(model.queueText == "1/2")
        #expect(model.approveTitle == "Yes")
    }

    // MARK: arming delay

    @Test func approveIsRefusedUntilTheRequestHasBeenShownForTheArmingDelay() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue, at: t0)

        let early = tracker.model(queue: queue, now: t0.addingTimeInterval(delay / 2))
        #expect(!early.canApprove)
        #expect(early.armsAt == t0.addingTimeInterval(delay))
        let began22 = tracker.begin(.approve, request: a, queue: queue, now: t0.addingTimeInterval(delay / 2))
        #expect(!began22)
        #expect(!tracker.model(queue: queue, now: t0.addingTimeInterval(delay / 2)).isBusy)

        let late = tracker.model(queue: queue, now: armed())
        #expect(late.canApprove)
        #expect(late.armsAt == nil)
        let began23 = tracker.begin(.approve, request: a, queue: queue, now: armed())
        #expect(began23)
    }

    @Test func denyIsAvailableDuringTheArmingPeriod() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue)
        let now = t0.addingTimeInterval(0.1)
        #expect(tracker.model(queue: queue, now: now).canDeny)
        let began24 = tracker.begin(.deny, request: a, queue: queue, now: now)
        #expect(began24)
    }

    @Test func aRequestThatWasNeverObservedCannotBeApprovedYet() {
        let a = request("a")
        var tracker = ApprovalPromptTracker()
        // Never shown to the person: not even a long time after its first-seen time.
        let now = t0.addingTimeInterval(100)
        #expect(!tracker.model(queue: [a], now: now).canApprove)
        let began25 = tracker.begin(.approve, request: a, queue: [a], now: now)
        #expect(!began25)
    }

    @Test func theNextRequestInTheSamePanelIsArmedAgainAfterADecision() {
        // A double click on Approve must not approve the request that replaces the first.
        let a = request("a")
        let b = request("b", firstSeen: t0.addingTimeInterval(1))
        let queue = [a, b]
        var tracker = observed(queue, at: t0.addingTimeInterval(2))
        let began26 = tracker.begin(.approve, request: a, queue: queue, now: armed(t0.addingTimeInterval(2)))
        #expect(began26)
        tracker.finish(.approve, requestID: "a", failureCode: nil)

        let swap = armed(t0.addingTimeInterval(2)).addingTimeInterval(0.2)
        tracker.observe(queue: queue, now: swap)
        let model = tracker.model(queue: queue, now: swap.addingTimeInterval(0.1))
        #expect(model.current?.id == "b")
        #expect(!model.canApprove)
        let began27 = tracker.begin(.approve, request: b, queue: queue, now: swap.addingTimeInterval(0.1))
        #expect(!began27)
        // Deny is still there.
        #expect(model.canDeny)

        let later = swap.addingTimeInterval(delay)
        #expect(tracker.model(queue: queue, now: later).canApprove)
        let began28 = tracker.begin(.approve, request: b, queue: queue, now: later)
        #expect(began28)
    }

    @Test func observingAgainDoesNotRestartTheArmingClock() {
        let a = request("a")
        let queue = [a]
        var tracker = observed(queue, at: t0)
        tracker.observe(queue: queue, now: t0.addingTimeInterval(0.6))
        #expect(tracker.model(queue: queue, now: armed()).canApprove)
    }

    @Test func aBackwardsClockNeverMakesTheDelayLongerThanOneDelay() {
        let a = request("a")
        let queue = [a]
        let tracker = observed(queue, at: t0.addingTimeInterval(50))
        // The clock went back 40 s: still at most one delay from now.
        let now = t0.addingTimeInterval(10)
        let model = tracker.model(queue: queue, now: now)
        #expect(model.armsAt == now.addingTimeInterval(delay))
    }

    @Test func armingStartsAgainWhenARequestIsShownAfterThePanelClosed() {
        let a = request("a")
        var tracker = observed([a], at: t0)
        // The panel closed (nothing pending), then the same id came back as a new request.
        tracker.observe(queue: [], now: armed())
        let back = armed().addingTimeInterval(5)
        tracker.observe(queue: [a], now: back)
        #expect(!tracker.model(queue: [a], now: back.addingTimeInterval(0.2)).canApprove)
        #expect(tracker.model(queue: [a], now: back.addingTimeInterval(delay)).canApprove)
    }

    // MARK: content pinned to what was first shown

    @Test func theButtonMustCarryTheRequestAsDrawn() {
        let drawn = request("a", fingerprint: "8877665544332211")
        let live = request("a", fingerprint: "deadbeef01234567")
        var tracker = observed([drawn])
        // The service swapped the fingerprint after the person looked; the click carries the drawn one.
        let began29 = tracker.begin(.approve, request: drawn, queue: [live], now: armed())
        #expect(!began29)
        let began30 = tracker.begin(.deny, request: drawn, queue: [live], now: armed())
        #expect(!began30)
        #expect(!tracker.model(queue: [live], now: armed()).isBusy)
    }

    @Test func aFingerprintChangedAfterTheFirstSightingIsNeverApprovable() {
        let first = request("a", fingerprint: "8877665544332211")
        let changed = request("a", fingerprint: "deadbeef01234567")
        var tracker = observed([first])
        // The change lands; even before the next redraw the model refuses.
        let blocked = tracker.model(queue: [changed], now: armed())
        #expect(!blocked.canApprove)
        #expect(blocked.warning == "The fingerprint does not match what the server reports. Do not approve.")
        #expect(blocked.canDeny)
        let began31 = tracker.begin(.approve, request: changed, queue: [changed], now: armed())
        #expect(!began31)

        // After the redraw it is remembered, and changing back does not unblock it.
        tracker.observe(queue: [changed], now: armed())
        tracker.observe(queue: [first], now: armed().addingTimeInterval(5))
        let later = armed().addingTimeInterval(10)
        #expect(!tracker.model(queue: [first], now: later).canApprove)
        #expect(tracker.model(queue: [first], now: later).warning != nil)
        let began32 = tracker.begin(.approve, request: first, queue: [first], now: later)
        #expect(!began32)
        // Deny stays available.
        let began33 = tracker.begin(.deny, request: first, queue: [first], now: later)
        #expect(began33)
    }

    @Test func aChangedCodeOrRequesterNameUnderTheSameIdIsRefusedToo() {
        let first = request("a", code: "482915", name: "Mac Studio")
        var codeChanged = observed([first])
        let newCode = request("a", code: "482916", name: "Mac Studio")
        #expect(!codeChanged.model(queue: [newCode], now: armed()).canApprove)
        let began34 = codeChanged.begin(.approve, request: newCode, queue: [newCode], now: armed())
        #expect(!began34)

        let renamed = request("a", code: "482915", name: "Mac Pro")
        #expect(!observed([first]).model(queue: [renamed], now: armed()).canApprove)
    }

    @Test func anUnchangedRequestIsStillApprovableAfterTheArmingDelay() {
        let a = request("a")
        var tracker = observed([a])
        // Seen again and again with the same content, as the service republishes.
        tracker.observe(queue: [a], now: t0.addingTimeInterval(0.5))
        tracker.observe(queue: [a], now: armed())
        let model = tracker.model(queue: [a], now: armed())
        #expect(model.canApprove)
        #expect(model.warning == nil)
        let began35 = tracker.begin(.approve, request: a, queue: [a], now: armed())
        #expect(began35)
    }

    @Test func aRequestThatWasSuspiciousOnceStaysBlockedIfTheFlagClears() {
        let flagged = request("a", suspicious: true)
        let cleared = request("a", suspicious: false)
        var tracker = observed([flagged])
        tracker.observe(queue: [cleared], now: t0.addingTimeInterval(0.5))
        #expect(!tracker.model(queue: [cleared], now: armed()).canApprove)
        let began36 = tracker.begin(.approve, request: cleared, queue: [cleared], now: armed())
        #expect(!began36)
    }

    @Test func aChangeToAQueuedRequestIsCaughtBeforeItBecomesCurrent() {
        let a = request("a")
        let b = request("b", firstSeen: t0.addingTimeInterval(5))
        let bChanged = request("b", fingerprint: "deadbeef01234567", firstSeen: t0.addingTimeInterval(5))
        var tracker = observed([a, b], at: t0.addingTimeInterval(10))
        // While "b" waits behind "a", its fingerprint changes.
        tracker.observe(queue: [a, bChanged], now: t0.addingTimeInterval(11))
        let began37 = tracker.begin(.deny, request: a, queue: [a, bChanged], now: armed(t0.addingTimeInterval(11)))
        #expect(began37)
        tracker.finish(.deny, requestID: "a", failureCode: nil)
        let now = armed(t0.addingTimeInterval(20))
        tracker.observe(queue: [a, bChanged], now: t0.addingTimeInterval(20))
        let model = tracker.model(queue: [a, bChanged], now: now)
        #expect(model.current?.id == "b")
        #expect(!model.canApprove)
        #expect(model.warning != nil)
    }

    @Test func pinsAreForgottenWhenTheServiceDropsTheId() {
        let first = request("a", fingerprint: "8877665544332211")
        let reused = request("a", fingerprint: "0102030405060708")
        var tracker = observed([first])
        tracker.observe(queue: [], now: t0.addingTimeInterval(1))
        // A different request that happens to reuse the id is pinned afresh.
        tracker.observe(queue: [reused], now: t0.addingTimeInterval(2))
        let now = armed(t0.addingTimeInterval(2))
        #expect(tracker.model(queue: [reused], now: now).canApprove)
    }
}
