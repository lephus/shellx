import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import XCTest
@testable import ShellX

/// The Ended page's trash as the signed-in scope wires it: the scope keeps the dismissals in the
/// `UserDefaults` it was made with, so the next launch's scope still has them.
@MainActor
final class EndedDismissalsWiringTests: XCTestCase {
    private func makeScope(defaults: UserDefaults) throws -> SignedInScope {
        let vault = AccountVault(store: InMemorySecretStore())
        let relay = FakeRelayAccount()
        let latency = LatencyLog()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ended-dismissals-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet([], phoneKey: { try await vault.phoneKey() }),
            latency: latency, defaults: defaults, sleep: { try await Task.sleep(for: $0) }, onUnauthorized: {})
        return AppComposition.makeScope(
            hub: hub, history: ConversationStore(directory: directory), latency: latency,
            launch: LaunchMark(latency: latency), pairing: PairingModel(hub: hub, relay: relay, vault: vault),
            defaults: defaults)
    }

    func testACardTakenOffTheEndedPageStaysOffAfterALaunch() throws {
        let suite = "EndedDismissalsWiringTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let now = Date()
        let endedMs = Int64(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)
        func ended(_ id: String) -> MachineSession {
            MachineSession(
                machineID: "m1", machineName: "MacBook Pro", online: true,
                session: AgentSession(
                    sessionId: id, agent: "claude", workspaceId: "", workspaceTitle: "", state: .ended,
                    stateSinceMs: endedMs, lastActivityMs: endedMs))
        }
        let sessions = [ended("a"), ended("b")]

        let scope = try makeScope(defaults: defaults)
        XCTAssertEqual(HomeFocus.make(sessions: sessions, pending: [], finished: [:], now: now).ended.count, 2)
        scope.endedDismissals.dismiss(sessions[0])
        let page = HomeFocus.make(
            sessions: sessions, pending: [], finished: [:], dismissed: scope.endedDismissals.dismissals, now: now)
        XCTAssertEqual(page.ended.map(\.session.session.sessionId), ["b"])

        let relaunched = try makeScope(defaults: defaults)
        let after = HomeFocus.make(
            sessions: sessions, pending: [], finished: [:], dismissed: relaunched.endedDismissals.dismissals,
            now: now)
        XCTAssertEqual(after.ended.map(\.session.session.sessionId), ["b"], "the home's fold counts one too")
    }
}
