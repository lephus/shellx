import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import XCTest

@testable import ShellXAppCore

/// Keeping the relay holding this phone's APNs token, and reading what a push says.
@MainActor
final class PushRegistrationTests: XCTestCase {
    private static let token = Data([0x00, 0xff, 0x10, 0xab])

    private func make(signedIn: Bool = true) async throws -> (PushRegistration, FakeRelayAccount, AccountVault) {
        let vault = AccountVault(store: InMemorySecretStore())
        if signedIn {
            try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        }
        let relay = FakeRelayAccount()
        return (PushRegistration(relay: relay, vault: vault, topic: "com.shellx.dev", environment: .sandbox), relay, vault)
    }

    private static func sets(_ relay: FakeRelayAccount) async -> [FakeRelayAccount.Call] {
        await relay.calls.filter { if case .setPushToken = $0 { true } else { false } }
    }

    func testANewTokenGoesToTheRelayAsHexWithTheAppAndHost() async throws {
        let (push, relay, _) = try await make()

        await push.tokenArrived(Self.token)

        let calls = await Self.sets(relay)
        XCTAssertEqual(calls, [.setPushToken(hexToken: "00ff10ab", topic: "com.shellx.dev", environment: .sandbox, token: "tok-1")])
    }

    func testTheSameTokenForTheSameSignInIsSentOnce() async throws {
        let (push, relay, _) = try await make()

        await push.tokenArrived(Self.token)
        await push.tokenArrived(Self.token)
        await push.signedIn()

        let calls = await Self.sets(relay)
        XCTAssertEqual(calls.count, 1)
    }

    func testATokenFromBeforeSignInIsSentOnceSignedIn() async throws {
        let (push, relay, vault) = try await make(signedIn: false)

        await push.tokenArrived(Self.token)
        let before = await Self.sets(relay)
        XCTAssertEqual(before, [])

        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d2", token: "tok-2", email: "a@b.c"))
        await push.signedIn()

        let after = await Self.sets(relay)
        XCTAssertEqual(after, [.setPushToken(hexToken: "00ff10ab", topic: "com.shellx.dev", environment: .sandbox, token: "tok-2")])
    }

    func testAFailedSendIsTriedAgainNextTime() async throws {
        let (push, relay, _) = try await make()
        await relay.setError(URLError(.notConnectedToInternet), for: .setPushToken)
        await push.tokenArrived(Self.token)

        await relay.setError(nil, for: .setPushToken)
        await push.signedIn()

        let calls = await Self.sets(relay)
        XCTAssertEqual(calls.count, 2)
    }

    func testComingBackToTheFrontSendsTheKnownTokenAgainInCaseTheRelayDroppedIt() async throws {
        let (push, relay, _) = try await make()
        await push.tokenArrived(Self.token)

        await push.appBecameActive()

        let calls = await Self.sets(relay)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.last, .setPushToken(hexToken: "00ff10ab", topic: "com.shellx.dev", environment: .sandbox, token: "tok-1"))
    }

    func testComingBackToTheFrontWithoutATokenSendsNothing() async throws {
        let (push, relay, _) = try await make()

        await push.appBecameActive()

        let calls = await Self.sets(relay)
        XCTAssertEqual(calls, [])
    }

    func testAnotherSignInSendsTheTokenAgain() async throws {
        let (push, relay, vault) = try await make()
        await push.tokenArrived(Self.token)

        try await vault.setSession(StoredSession(userID: "u2", deviceID: "d3", token: "tok-3", email: "b@b.c"))
        await push.signedIn()

        let calls = await Self.sets(relay)
        XCTAssertEqual(calls.last, .setPushToken(hexToken: "00ff10ab", topic: "com.shellx.dev", environment: .sandbox, token: "tok-3"))
        XCTAssertEqual(calls.count, 2)
    }
}

final class PushPayloadTests: XCTestCase {
    func testReadsANeedsYouPush() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["loc-key": "push.needsYou"]],
            "shellx": ["kind": "needs_you", "machine_id": "m1", "request_id": "r1"],
        ]
        XCTAssertEqual(PushPayload(userInfo: userInfo), .needsYou(machineID: "m1", requestID: "r1"))
    }

    func testReadsAResolvedPush() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1], "shellx": ["kind": "resolved", "machine_id": "m1", "request_id": "r1"],
        ]
        XCTAssertEqual(PushPayload(userInfo: userInfo), .resolved(machineID: "m1", requestID: "r1"))
    }

    func testAnythingElseIsNotOurs() {
        XCTAssertNil(PushPayload(userInfo: [:]))
        XCTAssertNil(PushPayload(userInfo: ["shellx": ["kind": "done", "machine_id": "m1", "request_id": "r1"]]))
        XCTAssertNil(PushPayload(userInfo: ["shellx": ["kind": "needs_you", "request_id": "r1"]]))
        XCTAssertNil(PushPayload(userInfo: ["shellx": ["kind": "needs_you", "machine_id": "m1", "request_id": 7]]))
    }
}
