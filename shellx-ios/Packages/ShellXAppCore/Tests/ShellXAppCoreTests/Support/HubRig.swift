import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// A signed-in hub connected to fake Macs and a store in a temporary directory, for the tests of
/// the agent screen's model, attachments and the stored chat copies. The hub's reconnect waits
/// wait on `backoff`.
@MainActor
struct HubRig {
    let hub: MachineHub
    let store: ConversationStore
    let directory: URL
    /// The hub's reconnect waits.
    let backoff: ManualSleeper

    /// `seed` runs on the store before the hub starts.
    static func make(
        _ macs: [FakeMac], in test: XCTestCase, seed: (ConversationStore) async -> Void = { _ in }
    ) async throws -> HubRig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-rig-\(UUID().uuidString)", isDirectory: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        await seed(store)

        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines(macs.map(\.machine), owner: "u1")
        let suite = "HubRig-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        test.addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let backoff = ManualSleeper()
        let hub = MachineHub(
            vault: vault, relay: FakeRelayAccount(),
            connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }), latency: LatencyLog(),
            defaults: defaults, sleep: backoff.sleep, onUnauthorized: {})
        test.addTeardownBlock { await hub.stopAll() }
        await hub.start()
        return HubRig(hub: hub, store: store, directory: directory, backoff: backoff)
    }

    /// Waits until every Mac is online and the hub lists `sessions` live sessions.
    func online(sessions: Int) async -> Bool {
        await eventually {
            hub.machines.allSatisfy { $0.state == .online } && hub.liveSessions.count == sessions
        }
    }
}

func liveSession(
    _ id: String, mac: String = "m1", online: Bool = true, state: AgentState = .working, activity: Int64?,
    since: Int64? = 1_700_000_000_000
) -> MachineSession {
    MachineSession(
        machineID: mac, machineName: "Mac \(mac)", online: online,
        session: agentSession(id, state: state, lastActivityMs: activity, stateSinceMs: since))
}
