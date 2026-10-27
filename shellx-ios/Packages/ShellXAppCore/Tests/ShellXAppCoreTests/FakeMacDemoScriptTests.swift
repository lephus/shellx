import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The Debug demo's "Mac giả" (`SHELLX_DEMO=1`): what the app shows while P2 is not on a real Mac.
@MainActor
final class FakeMacDemoScriptTests: XCTestCase {
    private func hub(for mac: FakeMac) async throws -> MachineHub {
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines([mac.machine], owner: "u1")
        let suite = "FakeMacDemoScriptTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let hub = MachineHub(
            vault: vault, relay: FakeRelayAccount(), connector: FakeMacFleet([mac], phoneKey: { try await vault.phoneKey() }),
            latency: LatencyLog(), defaults: UserDefaults(suiteName: suite)!, sleep: instantSleep, onUnauthorized: {})
        addTeardownBlock { await hub.stopAll() }
        await hub.start()
        return hub
    }

    private var kinds: (MachineHub) -> [PendingItem.Kind] { { $0.pendingItems.map(\.item.kind) } }

    func testSetUpServesTwoWorkingSessionsAndEveryChatKind() async throws {
        let mac = FakeMac(name: "Mac giả")
        let script = FakeMacDemoScript(mac: mac)
        await script.setUp()
        let hub = try await hub(for: mac)

        let ready = await eventually { hub.liveSessions.count == 2 }
        XCTAssertTrue(ready)
        XCTAssertEqual(hub.liveSessions.map(\.session.state), [.working, .working])
        XCTAssertEqual(Set(hub.liveSessions.map(\.session.agent)), ["claude"])

        var roles: Set<String> = []
        var entryKinds: Set<String> = []
        for session in hub.liveSessions {
            let page = try await hub.chatHistory(session.ref, beforeSeq: nil, limit: 50)
            roles.formUnion(page.entries.map(\.role.wire))
            entryKinds.formUnion(page.entries.map(\.kind.wire))
        }
        XCTAssertEqual(roles, ["user", "agent", "system"])
        XCTAssertEqual(entryKinds, ["prose", "thought", "tool_use", "status"])
    }

    func testStepsAddPermissionQuestionPlanInTurnAndFlipSessions() async throws {
        let mac = FakeMac(name: "Mac giả")
        let script = FakeMacDemoScript(mac: mac)
        await script.setUp()
        let hub = try await hub(for: mac)
        _ = await eventually { hub.liveSessions.count == 2 }

        for index in 0..<3 { await script.step(index) }

        let all = await eventually { hub.pendingItems.count == 3 }
        XCTAssertTrue(all)
        XCTAssertEqual(kinds(hub), [.permission, .question, .exitPlan])
        let question = hub.pendingItems[1].item
        XCTAssertEqual(question.modes, [])
        XCTAssertFalse(question.questions?.first?.options.isEmpty ?? true)
        XCTAssertNotNil(hub.pendingItems[2].item.planPreview)
        let flipped = await eventually { hub.liveSessions.contains { $0.session.state == .idle } }
        XCTAssertTrue(flipped, "a session went from working to idle")
    }

    func testPendingStaysBounded() async throws {
        let mac = FakeMac(name: "Mac giả")
        let script = FakeMacDemoScript(mac: mac)
        await script.setUp()
        let hub = try await hub(for: mac)

        for index in 0..<(FakeMacDemoScript.maxPending + 4) { await script.step(index) }

        let capped = await eventually { hub.pendingItems.count == FakeMacDemoScript.maxPending }
        XCTAssertTrue(capped, "\(hub.pendingItems.count)")
    }

    func testRunStepsEveryInterval() async throws {
        let mac = FakeMac(name: "Mac giả")
        let script = FakeMacDemoScript(mac: mac)
        let sleeper = ManualSleeper()
        let hub = try await hub(for: mac)
        let running = Task { await script.run(sleep: sleeper.sleep) }
        defer { running.cancel() }

        let waiting = await eventually { sleeper.waiting == [FakeMacDemoScript.interval] }
        XCTAssertTrue(waiting)
        XCTAssertEqual(hub.pendingItems.count, 0, "the first request comes after one interval")
        sleeper.release()
        let first = await eventually { kinds(hub) == [.permission] }
        XCTAssertTrue(first)

        running.cancel()
        await running.value
    }
}
