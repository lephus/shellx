import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// A signed-in hub connected to fake Macs, a store in a temporary directory, and a loaded
/// `HomeModel` over both, for the home tests. Saves wait on `saves`, reconnects on `backoff`.
@MainActor
struct HomeRig {
    static let now = Date(timeIntervalSince1970: 1_700_000_100)

    let hub: MachineHub
    let home: HomeModel
    let store: ConversationStore
    let directory: URL
    /// The home model's 0.5 s save delay.
    let saves: ManualSleeper
    /// The hub's reconnect waits.
    let backoff: ManualSleeper

    /// `seed` runs on the store before the home model loads it.
    static func make(
        _ macs: [FakeMac], in test: XCTestCase, seed: (ConversationStore) async -> Void = { _ in }
    ) async throws -> HomeRig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-model-\(UUID().uuidString)", isDirectory: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        await seed(store)

        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines(macs.map(\.machine), owner: "u1")
        let suite = "HomeRig-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        test.addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let backoff = ManualSleeper()
        let hub = MachineHub(
            vault: vault, relay: FakeRelayAccount(),
            connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }), latency: LatencyLog(),
            defaults: defaults, sleep: backoff.sleep, onUnauthorized: {})
        test.addTeardownBlock { await hub.stopAll() }
        await hub.start()

        let saves = ManualSleeper()
        let home = HomeModel(hub: hub, store: store, now: { now }, sleep: saves.sleep)
        // Ends a save still waiting on `saves`.
        test.addTeardownBlock { @MainActor in await home.flush() }
        await home.load()
        return HomeRig(hub: hub, home: home, store: store, directory: directory, saves: saves, backoff: backoff)
    }

    /// Another home model over the same hub and store, as after a relaunch; loaded.
    func reopened() async -> HomeModel {
        let home = HomeModel(hub: hub, store: store, now: { Self.now }, sleep: ManualSleeper().sleep)
        await home.load()
        return home
    }

    /// Runs `home.run()` until the test ends; returns once it watches the hub.
    func startRunning(in test: XCTestCase) async -> Bool {
        let home = self.home
        let task = Task { await home.run() }
        test.addTeardownBlock { task.cancel() }
        return await eventually { home.isObserving }
    }

    /// Waits until every Mac is online and the hub lists `sessions` live sessions.
    func online(sessions: Int) async -> Bool {
        await eventually {
            hub.machines.allSatisfy { $0.state == .online } && hub.liveSessions.count == sessions
        }
    }

    /// The stored home document, if one was written.
    func stored() async -> HomeDocument? {
        await store.load(.home, as: HomeDocument.self)
    }
}

/// Builds `HomeEntry` values for stored documents.
func homeEntry(_ index: Int, text: String? = nil) -> HomeEntry {
    HomeEntry(
        id: "e\(index)", at: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
        content: .userSaid(text: text ?? "message \(index)", target: nil, viaVoice: false))
}

func liveSession(
    _ id: String, mac: String = "m1", online: Bool = true, state: AgentState = .working, activity: Int64?,
    since: Int64? = 1_700_000_000_000
) -> MachineSession {
    MachineSession(
        machineID: mac, machineName: "Mac \(mac)", online: online,
        session: agentSession(id, state: state, lastActivityMs: activity, stateSinceMs: since))
}
