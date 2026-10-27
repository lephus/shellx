import Foundation
import ShellXLinkAccount
import XCTest

@testable import ShellXAppCore

final class AccountVaultTests: XCTestCase {
    private func machine(_ id: String) -> PairedMachine {
        PairedMachine(machineID: id, name: "Mac \(id)", linkSlot: "slot-\(id)", hostKey: Data(repeating: 7, count: 32))
    }

    func testPhoneKeyCreatedOnceAndReused() async throws {
        let store = InMemorySecretStore()
        let vault = AccountVault(store: store)
        let first = try await vault.phoneKey()
        let second = try await vault.phoneKey()
        XCTAssertEqual(first.publicKey, second.publicKey)
        XCTAssertEqual(first.rawPrivate.count, 32)
        XCTAssertEqual(store.writeCount(for: .phoneKey), 1)

        // A new vault over the same store (a relaunch) restores the same key.
        let relaunched = try await AccountVault(store: store).phoneKey()
        XCTAssertEqual(relaunched.publicKey, first.publicKey)
        XCTAssertEqual(store.writeCount(for: .phoneKey), 1)
    }

    func testSessionRoundTripAndRedactedDescription() async throws {
        let vault = AccountVault(store: InMemorySecretStore())
        let initial = try await vault.session()
        XCTAssertNil(initial)
        let session = StoredSession(userID: "u1", deviceID: "d1", token: "tok-secret", email: "a@b.c")
        try await vault.setSession(session)
        let stored = try await vault.session()
        XCTAssertEqual(stored, session)
        XCTAssertFalse("\(session)".contains("tok-secret"))
        XCTAssertFalse(String(reflecting: session).contains("tok-secret"))
        try await vault.clearSession()
        let cleared = try await vault.session()
        XCTAssertNil(cleared)
    }

    func testMachinesRoundTripWithOwner() async throws {
        let store = InMemorySecretStore()
        let vault = AccountVault(store: store)
        let none = try await vault.machines()
        let noOwner = try await vault.machinesOwner()
        XCTAssertEqual(none, [])
        XCTAssertNil(noOwner)

        try await vault.setMachines([machine("a"), machine("b")], owner: "u1")
        let machines = try await vault.machines()
        let owner = try await vault.machinesOwner()
        XCTAssertEqual(machines, [machine("a"), machine("b")])
        XCTAssertEqual(owner, "u1")

        let raw = try XCTUnwrap(store.read(.machines))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["owner"] as? String, "u1")
        XCTAssertEqual((json["machines"] as? [Any])?.count, 2)
    }

    func testWipeRemovesEveryItem() async throws {
        let store = InMemorySecretStore()
        let vault = AccountVault(store: store)
        try await vault.setSession(StoredSession(userID: "u", deviceID: "d", token: "t", email: "e"))
        _ = try await vault.phoneKey()
        try await vault.setMachines([machine("a")], owner: "u")
        try await vault.wipe()
        for item in SecretItem.allCases {
            XCTAssertNil(try store.read(item), "\(item) survived the wipe")
        }
    }

    func testUnavailableSurfaces() async throws {
        let store = InMemorySecretStore()
        store.failReads = .unavailable(status: -25308)
        let vault = AccountVault(store: store)
        do {
            _ = try await vault.session()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SecretStoreError, .unavailable(status: -25308))
        }
        do {
            _ = try await vault.phoneKey()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SecretStoreError, .unavailable(status: -25308))
        }
        XCTAssertEqual(store.writeCount(for: .phoneKey), 0, "an unreadable store must not get a fresh key")
    }
}
