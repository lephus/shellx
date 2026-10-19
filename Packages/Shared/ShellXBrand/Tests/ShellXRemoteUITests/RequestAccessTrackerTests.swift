import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

private func op(
    _ id: String, _ code: String, _ t: TimeInterval,
    _ status: OutgoingPairing.Status = .waiting, machine: String = "m1"
) -> OutgoingPairing {
    OutgoingPairing(
        id: id, toMachineID: machine, code: code, ownFingerprint: "a1b2c3d4e5f60718",
        status: status, createdAt: Date(timeIntervalSince1970: t)
    )
}

private func shown(_ pairing: OutgoingPairing) -> RequestAccessModel {
    RequestAccessModel(pairing: pairing, machineName: "MacBook Air")
}

@Suite struct RequestAccessTrackerTests {
    @Test func followsThePairingWithTheExpectedCode() {
        let tracker = RequestAccessTracker(machineID: "m1", expectedCode: "333333")
        let outgoing = [op("old", "111111", 10, .expired), op("new", "333333", 20), op("other", "222222", 50, machine: "m2")]
        #expect(tracker.current(in: outgoing)?.id == "new")
        // Nothing is shown until the service publishes the requested pairing.
        #expect(tracker.current(in: [op("old", "111111", 10, .expired)]) == nil)
    }

    @Test func followCanSwitchToTheCodeTheHeaderShows() {
        var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "111111")
        let outgoing = [op("a", "111111", 10), op("b", "333333", 20)]
        #expect(tracker.current(in: outgoing)?.id == "a")
        tracker.follow(expectedCode: nil)
        #expect(tracker.current(in: outgoing)?.id == "a")
        tracker.follow(expectedCode: "333333")
        #expect(tracker.current(in: outgoing)?.id == "b")
    }

    @Test func retryShowsNothingThenFollowsTheNewPairing() {
        var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "111111")
        let expired = op("p1", "111111", 10, .expired)
        let older = op("p0", "111111", 5, .expired)
        #expect(tracker.current(in: [older, expired])?.id == "p1")

        let started = tracker.beginRetry(from: shown(expired))
        #expect(started)
        #expect(tracker.isRetrying)
        // While the request is in flight neither pairing is shown.
        #expect(tracker.current(in: [older, expired]) == nil)

        tracker.finishRetry(code: "333333")
        #expect(!tracker.isRetrying)
        // The new pairing is not published yet: still nothing, never the old one.
        #expect(tracker.current(in: [older, expired]) == nil)
        let fresh = op("p2", "333333", 20)
        #expect(tracker.current(in: [older, expired, fresh])?.id == "p2")
    }

    @Test func retryWithTheSameCodeSkipsTheSupersededPairing() {
        // A service that reuses the code (the DEBUG fixture does).
        var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "123456")
        let expired = op("p1", "123456", 10, .expired)
        let started = tracker.beginRetry(from: shown(expired))
        #expect(started)
        tracker.finishRetry(code: "123456")
        #expect(tracker.current(in: [expired]) == nil)
        let fresh = op("p2", "123456", 20)
        #expect(tracker.current(in: [expired, fresh])?.id == "p2")
    }

    @Test func failedRetryBringsTheOldPairingBack() {
        var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "111111")
        let failed = op("p1", "111111", 10, .failed(code: "network"))
        let started = tracker.beginRetry(from: shown(failed))
        #expect(started)
        #expect(tracker.current(in: [failed]) == nil)
        tracker.finishRetry(code: nil)
        #expect(!tracker.isRetrying)
        #expect(tracker.current(in: [failed])?.id == "p1")
        // and "Try again" can be pressed again
        let again = tracker.beginRetry(from: shown(failed))
        #expect(again)
    }

    @Test func retryIsOnlyOfferedForExpiredOrFailed() {
        for status in [OutgoingPairing.Status.waiting, .approved, .denied] {
            var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "111111")
            let started = tracker.beginRetry(from: shown(op("p1", "111111", 10, status)))
            #expect(!started)
            #expect(!tracker.isRetrying)
        }
        var empty = RequestAccessTracker(machineID: "m1", expectedCode: nil)
        let startedFromNothing = empty.beginRetry(from: nil)
        #expect(!startedFromNothing)

        for status in [OutgoingPairing.Status.expired, .failed(code: "rate_limited")] {
            var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "111111")
            let started = tracker.beginRetry(from: shown(op("p1", "111111", 10, status)))
            #expect(started)
        }
    }

    @Test func secondRetryWhileOneIsInFlightIsRefused() {
        var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "111111")
        let expired = shown(op("p1", "111111", 10, .expired))
        let first = tracker.beginRetry(from: expired)
        let second = tracker.beginRetry(from: expired)
        #expect(first)
        #expect(!second)
    }

    @Test func autoCloseFiresOncePerApprovedPairing() {
        var tracker = RequestAccessTracker(machineID: "m1", expectedCode: nil)
        let first = tracker.takeAutoClose(for: "p1")
        let repeated = tracker.takeAutoClose(for: "p1")
        let other = tracker.takeAutoClose(for: "p2")
        #expect(first)
        #expect(!repeated)
        #expect(other)
    }

    @Test func stoppedTrackerShowsNothingAndRefusesWork() {
        var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "111111")
        let expired = op("p1", "111111", 10, .expired)
        let approved = op("p2", "111111", 20, .approved)
        #expect(tracker.current(in: [expired, approved])?.id == "p2")
        tracker.stop()
        #expect(tracker.isStopped)
        // A dismissed sheet must not start a retry, or open a session after approval.
        #expect(tracker.current(in: [expired, approved]) == nil)
        let retry = tracker.beginRetry(from: shown(expired))
        let autoClose = tracker.takeAutoClose(for: "p2")
        #expect(!retry)
        #expect(!autoClose)
        tracker.follow(expectedCode: "999999")
        #expect(tracker.expectedCode == "111111")
    }

    @Test func stoppingDuringARetryIgnoresItsResult() {
        var tracker = RequestAccessTracker(machineID: "m1", expectedCode: "111111")
        let expired = op("p1", "111111", 10, .expired)
        let started = tracker.beginRetry(from: shown(expired))
        #expect(started)
        tracker.stop()
        tracker.finishRetry(code: "333333")
        #expect(tracker.expectedCode == "111111")
        #expect(tracker.current(in: [expired, op("p2", "333333", 20)]) == nil)
    }
}
