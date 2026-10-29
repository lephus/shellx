import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

@MainActor
final class MachineHubUnpairTests: XCTestCase {
    private struct Rig {
        var hub: MachineHub
        var vault: AccountVault
        var relay: FakeRelayAccount
        var defaults: UserDefaults
        var unauthorized: Collected<Void>
    }

    private func grant(_ mac: FakeMac) -> PairedMachineListing {
        PairedMachineListing(
            grantID: "g-\(mac.machine.machineID)", machineID: mac.machine.machineID, name: mac.machine.name,
            platform: "macos", online: true, linkSlot: mac.machine.linkSlot, fingerprint: "f")
    }

    private func rig(_ macs: [FakeMac]) async throws -> Rig {
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines(macs.map(\.machine), owner: "u1")
        let relay = FakeRelayAccount()
        await relay.setGrants(macs.map(grant))
        let suite = "MachineHubUnpairTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let unauthorized = Collected<Void>()
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }),
            latency: LatencyLog(), defaults: defaults, sleep: instantSleep,
            onUnauthorized: { unauthorized.items.append(()) })
        addTeardownBlock { await hub.stopAll() }
        await hub.start()
        let online = await eventually { hub.machines.allSatisfy { $0.state == .online } }
        XCTAssertTrue(online, "\(hub.machines.map(\.state))")
        await relay.resetCalls()
        return Rig(hub: hub, vault: vault, relay: relay, defaults: defaults, unauthorized: unauthorized)
    }

    private func ids(_ hub: MachineHub) -> [String] { hub.machines.map(\.id) }

    private func assertThrows(
        _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
    ) async -> (any Error)? {
        do {
            try await body()
            XCTFail("expected an error", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Brief tests

    func testUnpairCallsRelayThenForgets() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        let rig = try await rig([a, b])

        try await rig.hub.unpair(machineID: a.machine.machineID)

        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [
            .machines(token: "tok-1"), .unpair(grantID: "g-\(a.machine.machineID)", token: "tok-1"),
        ])
        XCTAssertEqual(ids(rig.hub), [b.machine.machineID])
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [b.machine])
        let owner = try await rig.vault.machinesOwner()
        XCTAssertEqual(owner, "u1")
        XCTAssertEqual(rig.hub.connectionCount, 1)
        let closed = await eventually { await a.liveSessionCount == 0 }
        XCTAssertTrue(closed, "the session to the unpaired Mac was closed")
        let live = await b.liveSessionCount
        XCTAssertEqual(live, 1, "the other Mac is untouched")
    }

    func testUnpairMissingGrantStillForgets() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        let rig = try await rig([a, b])

        // The relay no longer lists the Mac (removed on the Mac meanwhile).
        await rig.relay.setGrants([grant(b)])
        try await rig.hub.unpair(machineID: a.machine.machineID)
        var calls = await rig.relay.calls
        XCTAssertEqual(calls, [.machines(token: "tok-1")], "nothing to unpair")
        XCTAssertEqual(ids(rig.hub), [b.machine.machineID])

        // Listed, but gone by the time the delete arrives.
        await rig.relay.resetCalls()
        await rig.relay.setError(RelayAPIError.http(status: 404, code: "not_found"), for: .unpair)
        try await rig.hub.unpair(machineID: b.machine.machineID)
        calls = await rig.relay.calls
        XCTAssertEqual(calls, [
            .machines(token: "tok-1"), .unpair(grantID: "g-\(b.machine.machineID)", token: "tok-1"),
        ])
        XCTAssertEqual(ids(rig.hub), [])
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [])
    }

    func testUnpairNetworkErrorKeepsMachine() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let rig = try await rig([a])

        await rig.relay.setError(URLError(.notConnectedToInternet), for: .machines)
        var error = await assertThrows { try await rig.hub.unpair(machineID: a.machine.machineID) }
        XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        XCTAssertEqual(ids(rig.hub), [a.machine.machineID])
        var saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [a.machine])

        await rig.relay.setError(nil, for: .machines)
        await rig.relay.setError(URLError(.timedOut), for: .unpair)
        error = await assertThrows { try await rig.hub.unpair(machineID: a.machine.machineID) }
        XCTAssertEqual((error as? URLError)?.code, .timedOut)
        XCTAssertEqual(ids(rig.hub), [a.machine.machineID])
        saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [a.machine])
        XCTAssertEqual(rig.hub.machines.first?.state, .online, "the Mac stays connected")
    }

    func testDefaultMachineFallsBackWhenRemoved() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        let rig = try await rig([a, b])
        rig.hub.defaultMachineID = b.machine.machineID

        try await rig.hub.unpair(machineID: b.machine.machineID)

        XCTAssertEqual(rig.hub.defaultMachineID, a.machine.machineID)
        XCTAssertNil(rig.defaults.string(forKey: "shellx.defaultMachineID"), "the removed Mac is not remembered")

        try await rig.hub.unpair(machineID: a.machine.machineID)
        XCTAssertNil(rig.hub.defaultMachineID)
    }

    // MARK: - More

    /// A Mac that already removed this iPhone has no grant left: removing it needs no network.
    func testRemoveRevokedMacWorksOffline() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let b = FakeMac(name: "Mac mini")
        let rig = try await rig([a, b])
        await rig.relay.setGrants([grant(b)])
        await rig.hub.refreshGrants()
        XCTAssertEqual(rig.hub.machines.first?.state, .revoked)

        await rig.relay.setError(URLError(.notConnectedToInternet), for: .machines)
        try await rig.hub.unpair(machineID: a.machine.machineID)

        XCTAssertEqual(ids(rig.hub), [b.machine.machineID])
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [b.machine])
    }

    func testUnpairUnauthorizedReportsAndKeepsMachine() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let rig = try await rig([a])
        await rig.relay.setError(RelayAPIError.http(status: 401, code: "unauthorized"), for: .machines)

        _ = await assertThrows { try await rig.hub.unpair(machineID: a.machine.machineID) }

        XCTAssertEqual(rig.unauthorized.items.count, 1)
        XCTAssertEqual(ids(rig.hub), [a.machine.machineID])
    }

    func testUnpairUnknownMachineDoesNothing() async throws {
        let a = FakeMac(name: "MacBook Pro")
        let rig = try await rig([a])

        try await rig.hub.unpair(machineID: "never-paired")

        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
        XCTAssertEqual(ids(rig.hub), [a.machine.machineID])
    }

    func testVaultWriteFailureKeepsMachine() async throws {
        let store = InMemorySecretStore()
        let a = FakeMac(name: "MacBook Pro")
        let vault = AccountVault(store: store)
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines([a.machine], owner: "u1")
        let relay = FakeRelayAccount()
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet([a], phoneKey: { try await vault.phoneKey() }),
            latency: LatencyLog(), defaults: UserDefaults(suiteName: "MachineHubUnpairTests-\(UUID().uuidString)")!,
            sleep: instantSleep, onUnauthorized: {})
        addTeardownBlock { await hub.stopAll() }
        await hub.start()
        store.failWrites = .failed(status: -1)

        _ = await assertThrows { try await hub.unpair(machineID: a.machine.machineID) }

        XCTAssertEqual(ids(hub), [a.machine.machineID], "still listed: the vault still has it")
    }
}
