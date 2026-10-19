import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func request(
    _ id: String,
    name: String = "Mac Studio",
    code: String = "482915",
    fingerprint: String = "8877665544332211",
    suspicious: Bool = false,
    firstSeen: Date = t0
) -> PairingRequest {
    PairingRequest(
        id: id, fromMachineID: "m-\(id)", requesterName: name, code: code,
        fingerprint: fingerprint, suspicious: suspicious, firstSeen: firstSeen
    )
}

private let vi = ApprovalPromptLabels(
    title: "%@ muốn xem và điều khiển máy này",
    compare: "Chỉ chấp thuận nếu mã và vân tay khớp với màn hình máy kia.",
    suspicious: "Vân tay không khớp với thông tin máy chủ. Đừng chấp thuận.",
    approve: "Chấp thuận",
    deny: "Từ chối",
    queue: "%lld / %lld",
    network: "Không kết nối được relay.shellx.pro",
    codeLabel: "Mã",
    fingerprintLabel: "Vân tay"
)

@Suite struct ApprovalPromptModelTests {
    @Test func showsOldestRequestWithCodeAndFingerprint() {
        let older = request("a", name: "Mac Studio", code: "482915", fingerprint: "8877665544332211", firstSeen: t0)
        let younger = request("b", name: "MacBook Air", code: "730264", fingerprint: "1122334455667788",
                              firstSeen: t0.addingTimeInterval(30))
        // The service lists them newest first; the oldest still comes first.
        let m = ApprovalPromptModel(queue: [younger, older], now: t0.addingTimeInterval(60))
        #expect(m.current?.id == "a")
        #expect(m.title == "Mac Studio wants to view and control this Mac")
        #expect(m.compareText == "Approve only if the code and fingerprint match the other screen.")
        #expect(m.codeText == "482 915")
        #expect(m.fingerprintText == "8877 6655 4433 2211")
        #expect(m.warning == nil)
        #expect(m.errorText == nil)
        #expect(m.canApprove)
        #expect(m.canDeny)
        #expect(m.approveTitle == "Approve")
        #expect(m.denyTitle == "Deny")
        #expect(m.codeLabel == "Code")
        #expect(m.fingerprintLabel == "Fingerprint")
    }

    @Test func fingerprintIsAlwaysShownWithTheCode() {
        for suspicious in [false, true] {
            let m = ApprovalPromptModel(queue: [request("a", suspicious: suspicious)], now: t0)
            #expect(!m.codeText.isEmpty)
            #expect(!m.fingerprintText.isEmpty)
        }
    }

    @Test func suspiciousRequestCannotBeApproved() {
        let m = ApprovalPromptModel(
            queue: [request("a", fingerprint: "deadbeef01234567", suspicious: true)], now: t0
        )
        #expect(m.current?.id == "a")
        #expect(!m.canApprove)
        #expect(m.warning == "The fingerprint does not match what the server reports. Do not approve.")
        // The fingerprint is still shown so the person can see what the other screen says.
        #expect(m.fingerprintText == "dead beef 0123 4567")
        // Deny stays available.
        #expect(m.canDeny)
    }

    @Test func expiredRequestsAreDropped() {
        let r = request("a", firstSeen: t0)
        let after = ApprovalPromptModel(queue: [r], now: t0.addingTimeInterval(301))
        #expect(after.current == nil)
        #expect(after.queueText == nil)
        #expect(after.title.isEmpty)
        #expect(after.codeText.isEmpty)
        #expect(after.fingerprintText.isEmpty)
        #expect(!after.canApprove)
        #expect(!after.canDeny)
        #expect(after.nextExpiry == nil)

        // `now >= expiresAt` drops it: exactly 300 s is already expired, 299 s is not.
        #expect(ApprovalPromptModel(queue: [r], now: t0.addingTimeInterval(300)).current == nil)
        #expect(ApprovalPromptModel(queue: [r], now: t0.addingTimeInterval(299)).current?.id == "a")
    }

    @Test func emptyQueueShowsNothing() {
        let m = ApprovalPromptModel(queue: [], now: t0)
        #expect(m.current == nil)
        #expect(m.queueText == nil)
        #expect(m.warning == nil)
        #expect(!m.canApprove)
        #expect(!m.canDeny)
    }

    @Test func queueTextCountsPending() {
        let a = request("a", firstSeen: t0)
        let b = request("b", firstSeen: t0.addingTimeInterval(10))
        let c = request("c", firstSeen: t0.addingTimeInterval(20))
        let now = t0.addingTimeInterval(30)
        // The queue label is "%lld / %lld" in the catalog's Vietnamese text.
        #expect(ApprovalPromptModel(queue: [a, b], now: now, labels: vi).queueText == "1 / 2")
        #expect(ApprovalPromptModel(queue: [a, b, c], now: now, labels: vi).queueText == "1 / 3")
        // English reads "1 of 2".
        #expect(ApprovalPromptModel(queue: [a, b], now: now).queueText == "1 of 2")
        // One pending request needs no counter.
        #expect(ApprovalPromptModel(queue: [a], now: now, labels: vi).queueText == nil)
        // An expired request is not pending.
        let later = t0.addingTimeInterval(305)
        let m = ApprovalPromptModel(queue: [a, b, c], now: later, labels: vi)
        #expect(m.current?.id == "b")
        #expect(m.queueText == "1 / 2")
    }

    @Test func nextRequestBecomesCurrentWhenTheOldestExpires() {
        let a = request("a", firstSeen: t0)
        let b = request("b", firstSeen: t0.addingTimeInterval(100))
        #expect(ApprovalPromptModel(queue: [b, a], now: t0.addingTimeInterval(299)).current?.id == "a")
        #expect(ApprovalPromptModel(queue: [b, a], now: t0.addingTimeInterval(300)).current?.id == "b")
        #expect(ApprovalPromptModel(queue: [b, a], now: t0.addingTimeInterval(400)).current == nil)
    }

    @Test func requestsSeenAtTheSameTimeKeepTheirListOrder() {
        let a = request("a")
        let b = request("b")
        #expect(ApprovalPromptModel(queue: [a, b], now: t0).current?.id == "a")
        #expect(ApprovalPromptModel(queue: [b, a], now: t0).current?.id == "b")
    }

    @Test func nextExpiryIsTheCurrentRequestsDeadline() {
        let a = request("a", firstSeen: t0)
        let b = request("b", firstSeen: t0.addingTimeInterval(50))
        let m = ApprovalPromptModel(queue: [b, a], now: t0.addingTimeInterval(10))
        #expect(m.nextExpiry == t0.addingTimeInterval(300))
    }

    @Test func fingerprintMismatchFromTheServiceIsShownAsTheSuspiciousTextAndBlocksApproval() {
        let m = ApprovalPromptModel(queue: [request("a")], now: t0, failureCode: "fingerprint_mismatch")
        #expect(m.warning == "The fingerprint does not match what the server reports. Do not approve.")
        #expect(m.errorText == nil)
        #expect(!m.canApprove)
        #expect(m.canDeny)
    }

    @Test func suspiciousRequestWithAMismatchShowsTheWarningOnce() {
        let m = ApprovalPromptModel(queue: [request("a", suspicious: true)], now: t0, failureCode: "fingerprint_mismatch")
        #expect(m.warning != nil)
        #expect(m.errorText == nil)
        #expect(!m.canApprove)
    }

    @Test func otherFailuresShowInlineAndKeepTheRequestApprovable() {
        let net = ApprovalPromptModel(queue: [request("a")], now: t0, failureCode: "network")
        #expect(net.errorText == "Can't reach relay.shellx.pro")
        #expect(net.warning == nil)
        #expect(net.canApprove)

        let viNet = ApprovalPromptModel(queue: [request("a")], now: t0, labels: vi, failureCode: "network")
        #expect(viNet.errorText == "Không kết nối được relay.shellx.pro")

        let other = ApprovalPromptModel(queue: [request("a")], now: t0, failureCode: "http_500")
        #expect(other.errorText == "http_500")
        #expect(other.canApprove)
    }

    @Test func aFailureOnASuspiciousRequestKeepsItNotApprovable() {
        let m = ApprovalPromptModel(queue: [request("a", suspicious: true)], now: t0, failureCode: "network")
        #expect(m.warning != nil)
        #expect(m.errorText == "Can't reach relay.shellx.pro")
        #expect(!m.canApprove)
    }

    @Test func busyDisablesBothButtons() {
        let m = ApprovalPromptModel(queue: [request("a")], now: t0, isBusy: true)
        #expect(m.isBusy)
        #expect(!m.canApprove)
        #expect(!m.canDeny)
        #expect(m.current?.id == "a")
    }

    @Test func vietnameseTextComesFromTheInjectedLabels() {
        let m = ApprovalPromptModel(
            queue: [request("a", name: "Máy tính văn phòng", suspicious: true)], now: t0, labels: vi
        )
        #expect(m.title == "Máy tính văn phòng muốn xem và điều khiển máy này")
        #expect(m.compareText == "Chỉ chấp thuận nếu mã và vân tay khớp với màn hình máy kia.")
        #expect(m.warning == "Vân tay không khớp với thông tin máy chủ. Đừng chấp thuận.")
        #expect(m.approveTitle == "Chấp thuận")
        #expect(m.denyTitle == "Từ chối")
    }

    @Test func aVeryLongNameStaysOneTitleForTheViewToTruncate() {
        let name = String(repeating: "Máy tính văn phòng tầng 3 ", count: 6)
        let m = ApprovalPromptModel(queue: [request("a", name: name)], now: t0, labels: vi)
        #expect(m.titleLineLimit == 1)
        #expect(m.title.hasPrefix("Máy tính văn phòng tầng 3 "))
        #expect(!m.title.contains("\n"))
    }

    @Test func approveWaitsForTheArmingMomentButDenyDoesNot() {
        let r = request("a")
        let armsAt = t0.addingTimeInterval(11)
        let early = ApprovalPromptModel(queue: [r], now: t0.addingTimeInterval(10), approvalArmsAt: armsAt)
        #expect(!early.canApprove)
        #expect(early.canDeny)
        #expect(early.armsAt == armsAt)
        // The warning is for fingerprint problems; waiting is not one.
        #expect(early.warning == nil)
        #expect(early.errorText == nil)

        let atTheMoment = ApprovalPromptModel(queue: [r], now: armsAt, approvalArmsAt: armsAt)
        #expect(atTheMoment.canApprove)
        #expect(atTheMoment.armsAt == nil)
        // Without a moment the request is armed (the plain model of the brief).
        #expect(ApprovalPromptModel(queue: [r], now: t0).canApprove)
    }

    @Test func aRequestChangedSinceItWasFirstShownShowsTheSuspiciousTextAndCannotBeApproved() {
        let m = ApprovalPromptModel(queue: [request("a")], now: t0, contentChanged: true)
        #expect(m.warning == "The fingerprint does not match what the server reports. Do not approve.")
        #expect(m.errorText == nil)
        #expect(!m.canApprove)
        #expect(m.canDeny)
    }

    @Test func nextWakeIsTheEarlierOfTheArmingMomentAndTheExpiry() {
        let r = request("a", firstSeen: t0)
        let armsAt = t0.addingTimeInterval(11)
        let m = ApprovalPromptModel(queue: [r], now: t0.addingTimeInterval(10), approvalArmsAt: armsAt)
        #expect(m.nextWake == armsAt)
        let armed = ApprovalPromptModel(queue: [r], now: t0.addingTimeInterval(12), approvalArmsAt: armsAt)
        #expect(armed.nextWake == t0.addingTimeInterval(300))
        #expect(ApprovalPromptModel(queue: [], now: t0).nextWake == nil)
    }

    @Test func modelsWithTheSameInputsAreEqual() {
        let r = request("a")
        #expect(ApprovalPromptModel(queue: [r], now: t0) == ApprovalPromptModel(queue: [r], now: t0))
        #expect(
            ApprovalPromptModel(queue: [r], now: t0)
                != ApprovalPromptModel(queue: [r], now: t0, failureCode: "network")
        )
    }
}
