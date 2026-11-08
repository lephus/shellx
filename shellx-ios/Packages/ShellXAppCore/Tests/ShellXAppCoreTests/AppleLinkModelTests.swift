import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest
@testable import ShellXAppCore

@MainActor
final class AppleLinkModelTests: XCTestCase {
    @MainActor private final class OutcomeLog { var all: [AppleLinkModel.Outcome] = [] }
    private struct Rig { let relay: FakeRelayAccount; let vault: AccountVault; let model: AppleLinkModel; let log: OutcomeLog }
    private let owner = AccountSignIn(session: AccountSession(userID: "owner", deviceID: "d9", token: "tok-a"), email: "owner@example.com")
    private let hostKey = Data(repeating: 4, count: 32)
    private func offer() -> PairingOffer { PairingOffer.make(machineID: "m1", linkSlot: "s1", hostKey: hostKey, machineName: "Studio") }
    private func rig() async -> Rig {
        let relay = FakeRelayAccount()
        await relay.setAppleLinkSignIn(owner)
        let vault = AccountVault(store: InMemorySecretStore())
        let log = OutcomeLog()
        let model = AppleLinkModel(linkToken: "link-1", relay: relay, vault: vault, finish: { log.all.append($0) })
        return Rig(relay: relay, vault: vault, model: model, log: log)
    }

    func testCodeIsReadWithoutTouchingTheRelay() async {
        let rig = await rig()
        rig.model.begin(uri: offer().uri.replacingOccurrences(of: "shellx-link:", with: "SHELLX-LINK:"))
        XCTAssertEqual(rig.model.step, .confirm(machineName: "Studio"))
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
    }

    func testConfirmLinksWithTheTokenAndThePhoneKey() async throws {
        let rig = await rig()
        let offer = offer()
        rig.model.begin(uri: offer.uri)
        await rig.model.confirm()
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.linkApple(offerURI: offer.uri, linkToken: "link-1", clientKey: key)])
        XCTAssertEqual(rig.log.all, [.linked(AppleLinkApproval(
            signIn: owner, machine: PairedMachine(machineID: "m1", name: "Studio", linkSlot: "s1", hostKey: hostKey)))])
        XCTAssertEqual(rig.model.step, .paired(machineName: "Studio"))
    }

    func testDeniedExpiredAndRefusedTokenEndTheLink() async {
        let cases: [(any Error, AppleLinkModel.Outcome)] = [
            (PhonePairingError.denied, .denied), (PhonePairingError.expired, .expired),
            (RelayAPIError.http(status: 401, code: "invalid_credentials"), .expired),
        ]
        for (error, outcome) in cases {
            let rig = await rig()
            await rig.relay.setError(error, for: .linkApple)
            rig.model.begin(uri: offer().uri)
            await rig.model.confirm()
            XCTAssertEqual(rig.log.all, [outcome], "\(error)")
        }
    }

    func testRetryableFailuresStayOnTheScanner() async {
        let cases: [(any Error, PairingFailure)] = [
            (URLError(.notConnectedToInternet), .network),
            (RelayAPIError.http(status: 404, code: "machine_not_found"), .otherAccount),
            (RelayAPIError.http(status: 500, code: "oops"), .server(code: "oops")),
        ]
        for (error, failure) in cases {
            let rig = await rig()
            await rig.relay.setError(error, for: .linkApple)
            rig.model.begin(uri: offer().uri)
            await rig.model.confirm()
            XCTAssertEqual(rig.model.step, .failed(failure), "\(error)")
            XCTAssertEqual(rig.log.all, [])
            rig.model.cancel()
            XCTAssertEqual(rig.model.step, .idle)
        }
        let rig = await rig()
        rig.model.begin(uri: "hello")
        XCTAssertEqual(rig.model.step, .failed(.notShellXCode))
    }

    func testCloseEndsTheLink() async {
        let rig = await rig()
        rig.model.begin(uri: offer().uri)
        rig.model.close()
        let ended = await eventually { rig.log.all == [.cancelled] }
        XCTAssertTrue(ended, "\(rig.log.all)")
        XCTAssertEqual(rig.model.step, .idle)
    }
}
