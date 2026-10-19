import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

private func pairing(_ status: OutgoingPairing.Status, id: String = "p1") -> OutgoingPairing {
    OutgoingPairing(
        id: id, toMachineID: "m1", code: "123456", ownFingerprint: "a1b2c3d4e5f60718",
        status: status, createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

private let vi = RequestAccessLabels(
    title: "Xin quyền vào %@",
    instructions: "Trên %@, chỉ chấp thuận nếu mã và vân tay khớp với màn hình này.",
    approved: "Đã được chấp thuận",
    denied: "Bị từ chối",
    expired: "Đã hết hạn",
    network: "Không kết nối được relay.shellx.pro"
)

@Suite struct RequestAccessModelTests {
    @Test func waitingShowsCodeFingerprintAndSpinner() {
        let m = RequestAccessModel(pairing: pairing(.waiting), machineName: "MacBook Air")
        #expect(m.title == "Request access to MacBook Air")
        #expect(m.codeText == "123 456")
        #expect(m.fingerprintText == "a1b2 c3d4 e5f6 0718")
        #expect(m.instructions == "On MacBook Air, approve only if the code and fingerprint match this screen.")
        #expect(m.showsSpinner)
        #expect(m.statusText == nil)
        #expect(m.statusTone == nil)
        #expect(m.primaryAction == nil)
        #expect(!m.closesAutomatically)
    }

    @Test func approvedClosesAutomatically() {
        let m = RequestAccessModel(pairing: pairing(.approved), machineName: "MacBook Air")
        #expect(m.statusText == "Approved")
        #expect(m.statusTone == .done)
        #expect(m.closesAutomatically)
        #expect(RequestAccessModel.autoCloseDelay == 1)
        #expect(!m.showsSpinner)
        #expect(m.primaryAction == nil)
        // The code and fingerprint stay on screen in every state.
        #expect(m.codeText == "123 456")
        #expect(m.fingerprintText == "a1b2 c3d4 e5f6 0718")
    }

    @Test func deniedShowsErrorWithoutRetry() {
        let m = RequestAccessModel(pairing: pairing(.denied), machineName: "MacBook Air")
        #expect(m.statusText == "Denied")
        #expect(m.statusTone == .error)
        #expect(m.primaryAction == nil)
        #expect(!m.showsSpinner)
        #expect(!m.closesAutomatically)
    }

    @Test func expiredOffersRetry() {
        let m = RequestAccessModel(pairing: pairing(.expired), machineName: "MacBook Air")
        #expect(m.statusText == "Expired")
        #expect(m.statusTone == .muted)
        #expect(m.primaryAction == .retry)
        #expect(!m.showsSpinner)
        #expect(!m.closesAutomatically)
    }

    @Test func failedOffersRetryWithReadableCode() {
        let other = RequestAccessModel(pairing: pairing(.failed(code: "rate_limited")), machineName: "MacBook Air")
        #expect(other.statusText == "rate_limited")
        #expect(other.statusTone == .error)
        #expect(other.primaryAction == .retry)
        #expect(!other.showsSpinner)
        #expect(!other.closesAutomatically)

        let network = RequestAccessModel(pairing: pairing(.failed(code: "network")), machineName: "MacBook Air", labels: vi)
        #expect(network.statusText == "Không kết nối được relay.shellx.pro")
        #expect(network.primaryAction == .retry)
    }

    @Test func vietnameseTitleTruncatesNotWraps() {
        let name = String(repeating: "Máy tính văn phòng tầng 3 ", count: 5).prefix(120)
        #expect(name.count == 120)
        let m = RequestAccessModel(pairing: pairing(.waiting), machineName: String(name), labels: vi)
        // The model keeps the whole name; the view truncates the single line.
        #expect(m.title == "Xin quyền vào " + name)
        #expect(m.titleLineLimit == 1)
        #expect(m.instructions.hasPrefix("Trên " + name + ","))
    }

    @Test func modelIsEquatableAcrossStatusChanges() {
        let waiting = RequestAccessModel(pairing: pairing(.waiting), machineName: "A")
        #expect(waiting == RequestAccessModel(pairing: pairing(.waiting), machineName: "A"))
        #expect(waiting != RequestAccessModel(pairing: pairing(.approved), machineName: "A"))
        #expect(waiting.pairingID == "p1")
    }
    @Test func currentPairingIsTheNewestForTheMachineSkippingSuperseded() {
        func op(_ id: String, _ machine: String, _ code: String, _ t: TimeInterval, _ s: OutgoingPairing.Status = .waiting) -> OutgoingPairing {
            OutgoingPairing(id: id, toMachineID: machine, code: code, ownFingerprint: "a1b2c3d4e5f60718",
                            status: s, createdAt: Date(timeIntervalSince1970: t))
        }
        let outgoing = [
            op("old", "m1", "111111", 10, .expired),
            op("other", "m2", "222222", 50),
            op("new", "m1", "333333", 20),
            op("stray", "m1", "999999", 30),
        ]
        // The code `requestAccess` returned wins over a newer pairing with another code.
        #expect(RequestAccessModel.currentPairing(in: outgoing, for: "m1", expectedCode: "333333", excluding: [])?.id == "new")
        // Without a matching code the newest for the machine is shown.
        #expect(RequestAccessModel.currentPairing(in: outgoing, for: "m1", expectedCode: nil, excluding: [])?.id == "stray")
        #expect(RequestAccessModel.currentPairing(in: outgoing, for: "m1", expectedCode: "000000", excluding: [])?.id == "stray")
        // A retried pairing is never shown again, even with the same code.
        #expect(RequestAccessModel.currentPairing(in: outgoing, for: "m1", expectedCode: "111111", excluding: ["old", "stray"])?.id == "new")
        #expect(RequestAccessModel.currentPairing(in: outgoing, for: "m1", expectedCode: nil, excluding: ["old", "new", "stray"]) == nil)
        #expect(RequestAccessModel.currentPairing(in: outgoing, for: "m3", expectedCode: nil, excluding: []) == nil)
    }
}
