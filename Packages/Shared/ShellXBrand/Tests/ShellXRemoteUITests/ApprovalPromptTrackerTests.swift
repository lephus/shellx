import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func request(
    _ id: String,
    suspicious: Bool = false,
    firstSeen: Date = t0
) -> PairingRequest {
    PairingRequest(
        id: id, fromMachineID: "m-\(id)", requesterName: "Mac \(id)", code: "482915",
        fingerprint: "8877665544332211", suspicious: suspicious, firstSeen: firstSeen
    )
}

@Suite struct ApprovalPromptTrackerTests {
    @Test func approvingTheShownRequestStartsAndThenHidesItEvenIfTheServiceStillListsIt() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a"), request("b", firstSeen: t0.addingTimeInterval(5))]
        let started = tracker.begin(.approve, requestID: "a", queue: queue, now: t0.addingTimeInterval(10))
        #expect(started)
        #expect(tracker.model(queue: queue, now: t0.addingTimeInterval(10)).isBusy)

        tracker.finish(.approve, requestID: "a", failureCode: nil)
        let model = tracker.model(queue: queue, now: t0.addingTimeInterval(11))
        #expect(!model.isBusy)
        // The service has not dropped "a" yet; the panel already moved on.
        #expect(model.current?.id == "b")
        #expect(model.queueText == nil)
    }

    @Test func suspiciousRequestIsNeverApprovedButCanBeDenied() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a", suspicious: true)]
        let began1 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(!began1)
        #expect(!tracker.model(queue: queue, now: t0).isBusy)
        let began2 = tracker.begin(.deny, requestID: "a", queue: queue, now: t0)
        #expect(began2)
    }

    @Test func aStaleButtonCannotActOnADifferentRequest() {
        // The person saw "a"; by the time the click lands "b" is on screen.
        var tracker = ApprovalPromptTracker()
        let queue = [request("b", firstSeen: t0.addingTimeInterval(100))]
        let began3 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0.addingTimeInterval(310))
        #expect(!began3)
        let began4 = tracker.begin(.deny, requestID: "a", queue: queue, now: t0.addingTimeInterval(310))
        #expect(!began4)
        #expect(!tracker.model(queue: queue, now: t0.addingTimeInterval(310)).isBusy)
    }

    @Test func aRequestThatIsNotTheOldestCannotBeActedOn() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a"), request("b", firstSeen: t0.addingTimeInterval(5))]
        let began5 = tracker.begin(.approve, requestID: "b", queue: queue, now: t0.addingTimeInterval(10))
        #expect(!began5)
    }

    @Test func anExpiredRequestCannotBeApprovedOrDenied() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a")]
        let began6 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0.addingTimeInterval(300))
        #expect(!began6)
        let began7 = tracker.begin(.deny, requestID: "a", queue: queue, now: t0.addingTimeInterval(301))
        #expect(!began7)
    }

    @Test func onlyOneDecisionIsInFlightAtATime() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a")]
        let began8 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(began8)
        let began9 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(!began9)
        let began10 = tracker.begin(.deny, requestID: "a", queue: queue, now: t0)
        #expect(!began10)
    }

    @Test func aFailedApproveShowsInlineAndAllowsAnotherTry() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a")]
        let began11 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(began11)
        tracker.finish(.approve, requestID: "a", failureCode: "network")

        let model = tracker.model(queue: queue, now: t0)
        #expect(model.current?.id == "a")
        #expect(model.errorText == "Can't reach relay.shellx.pro")
        #expect(!model.isBusy)
        #expect(model.canApprove)
        // A new attempt clears the old message while it runs.
        let began12 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(began12)
        #expect(tracker.model(queue: queue, now: t0).errorText == nil)
    }

    @Test func aFingerprintMismatchFromTheServiceBlocksApprovingThatRequest() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a"), request("b", firstSeen: t0.addingTimeInterval(5))]
        let began13 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(began13)
        tracker.finish(.approve, requestID: "a", failureCode: "fingerprint_mismatch")

        let model = tracker.model(queue: queue, now: t0)
        #expect(model.warning == "The fingerprint does not match what the server reports. Do not approve.")
        #expect(!model.canApprove)
        let began14 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(!began14)
        let began15 = tracker.begin(.deny, requestID: "a", queue: queue, now: t0)
        #expect(began15)
    }

    @Test func aFailureBelongsToItsRequestOnly() {
        var tracker = ApprovalPromptTracker()
        let a = request("a")
        let b = request("b", firstSeen: t0.addingTimeInterval(5))
        let began16 = tracker.begin(.approve, requestID: "a", queue: [a, b], now: t0)
        #expect(began16)
        tracker.finish(.approve, requestID: "a", failureCode: "network")
        // "a" is denied by someone else / gone; "b" is shown without a's error.
        let model = tracker.model(queue: [b], now: t0)
        #expect(model.current?.id == "b")
        #expect(model.errorText == nil)
    }

    @Test func decidedAndFailedRequestsAreForgottenOnceTheServiceDropsThem() {
        var tracker = ApprovalPromptTracker()
        let a = request("a")
        let began17 = tracker.begin(.deny, requestID: "a", queue: [a], now: t0)
        #expect(began17)
        tracker.finish(.deny, requestID: "a", failureCode: nil)
        #expect(tracker.model(queue: [a], now: t0).current == nil)

        tracker.prune(queue: [])
        // A new request that reuses the id is a new request and shows again.
        #expect(tracker.model(queue: [a], now: t0).current?.id == "a")
    }

    @Test func nothingStartsOnceStopped() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a")]
        tracker.stop()
        #expect(tracker.isStopped)
        let began18 = tracker.begin(.deny, requestID: "a", queue: queue, now: t0)
        #expect(!began18)
        let began19 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(!began19)
    }

    @Test func aResultAfterStopChangesNothingVisible() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a")]
        let began20 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(began20)
        tracker.stop()
        tracker.finish(.approve, requestID: "a", failureCode: nil)
        // Stopped: no decision is recorded that could hide a request later.
        #expect(tracker.model(queue: queue, now: t0).current?.id == "a")
    }

    @Test func aFinishForAnotherRequestIsIgnored() {
        var tracker = ApprovalPromptTracker()
        let queue = [request("a")]
        let began21 = tracker.begin(.approve, requestID: "a", queue: queue, now: t0)
        #expect(began21)
        tracker.finish(.approve, requestID: "zzz", failureCode: nil)
        #expect(tracker.model(queue: queue, now: t0).isBusy)
    }

    @Test func modelCarriesTheLabelsItIsGiven() {
        let tracker = ApprovalPromptTracker()
        let labels = ApprovalPromptLabels(
            title: "%@ wants in", compare: "c", suspicious: "s", approve: "Yes", deny: "No",
            queue: "%lld/%lld", network: "n", codeLabel: "Code", fingerprintLabel: "FP"
        )
        let model = tracker.model(queue: [request("a"), request("b", firstSeen: t0.addingTimeInterval(1))], now: t0, labels: labels)
        #expect(model.title == "Mac a wants in")
        #expect(model.queueText == "1/2")
        #expect(model.approveTitle == "Yes")
    }
}
