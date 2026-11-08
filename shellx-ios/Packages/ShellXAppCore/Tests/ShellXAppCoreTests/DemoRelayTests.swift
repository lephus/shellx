import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest
@testable import ShellXAppCore

final class DemoRelayTests: XCTestCase {
    private let a = PairedMachine(machineID: "mac-a", name: "Mac A", linkSlot: "slot-a", hostKey: Data(repeating: 1, count: 32))
    private func offer(_ id: String) -> PairingOffer {
        PairingOffer.make(machineID: id, linkSlot: "slot-\(id)", hostKey: Data(repeating: 2, count: 32), machineName: "Mac \(id)")
    }

    func testListsPairsAndUnpairsTheDemoMacs() async throws {
        let relay = DemoRelay(paired: [a], pairableMachineIDs: ["mac-b"], approvalDelay: .zero)
        let first = try await relay.machines(token: "demo-token")
        XCTAssertEqual(first.map(\.machineID), ["mac-a"])
        let paired = try await relay.pair(offerURI: offer("mac-b").uri, clientKey: Data(repeating: 3, count: 32), token: "demo-token")
        XCTAssertEqual(paired, PairedMachine(machineID: "mac-b", name: "Mac mac-b", linkSlot: "slot-mac-b", hostKey: Data(repeating: 2, count: 32)))
        let both = try await relay.machines(token: "demo-token")
        XCTAssertEqual(both.map(\.machineID), ["mac-a", "mac-b"])
        try await relay.unpair(grantID: "grant-mac-a", token: "demo-token")
        let left = try await relay.machines(token: "demo-token")
        XCTAssertEqual(left.map(\.machineID), ["mac-b"])
    }

    func testCodesOfOtherMacsAreRefused() async {
        let relay = DemoRelay(paired: [], pairableMachineIDs: ["mac-b"], approvalDelay: .zero)
        do { _ = try await relay.pair(offerURI: offer("mac-z").uri, clientKey: Data(repeating: 3, count: 32), token: "t"); XCTFail() } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 404, code: "machine_not_found"))
        }
    }

    func testEveryAccountCallIsRefused() async {
        let relay = DemoRelay(paired: [], pairableMachineIDs: [], approvalDelay: .zero)
        let key = Data(repeating: 3, count: 32)
        let calls: [(String, @Sendable () async throws -> Void)] = [
            ("login", { _ = try await relay.login(email: "a", password: "b", deviceName: "p", clientKey: key) }),
            ("nonce", { _ = try await relay.nonce() }),
            ("signInWithGoogle", { _ = try await relay.signInWithGoogle(idToken: "i", nonce: "n", deviceName: "p", clientKey: key) }),
            ("linkGoogle", { _ = try await relay.linkGoogle(idToken: "i", nonce: "n", token: "t") }),
            ("signInWithApple", { _ = try await relay.signInWithApple(identityToken: "i", authorizationCode: "c", nonce: "n", deviceName: "p", clientKey: key) }),
            ("linkApple", { _ = try await relay.linkApple(offerURI: "u", linkToken: "l", clientKey: key) }),
            ("deleteAccount", { try await relay.deleteAccount(idToken: "i", nonce: "n", token: "t") }),
        ]
        for (name, call) in calls {
            do { try await call(); XCTFail(name) } catch { XCTAssertEqual(error as? RelayAPIError, DemoRelay.refusal, name) }
        }
    }

    func testDemoSecretsStayInMemory() throws {
        let store = DemoSecretStore()
        try store.write(Data("x".utf8), for: .session)
        XCTAssertEqual(try store.read(.session), Data("x".utf8))
        try store.delete(.session)
        XCTAssertNil(try store.read(.session))
    }
}
