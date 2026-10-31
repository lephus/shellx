import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import XCTest
@testable import ShellX

/// A signed-in scope, made as `AppComposition` makes it, over a hub connected to a fake Mac that has two
/// workspaces and one Claude Code session, with the model and actions of one workspace's screen; for the
/// tests of `WorkspaceView`.
@MainActor
struct WorkspaceRig {
    /// What the actions did to the screen.
    final class Screen {
        var alerts: [WorkspaceAlert] = []
        var closings = 0
        var tasks: [Task<WorkspaceFeedback, Never>] = []
    }

    let scope: SignedInScope
    let model: WorkspaceScreenModel
    let screen: Screen
    let actions: WorkspaceScreenActions
    let mac: FakeMac

    var hub: MachineHub { scope.hub }

    /// The feedback of the command the last action started.
    func lastFeedback() async -> WorkspaceFeedback? {
        await screen.tasks.last?.value
    }

    static func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    /// `ws-shellx` has the agent `claude` (session `s1`, working) and a shell `zsh` (the Mac's selection);
    /// `ws-web` has one shell. `name` is the workspace the model looks at: `new` is one the Mac does not list.
    /// With `acceptsAgentClose` false the Mac is one from before `agent_close`.
    static func make(
        opening name: String = "shellx", acceptsAgentClose: Bool = true, in test: XCTestCase
    ) async throws -> WorkspaceRig {
        let mac = FakeMac(name: "MacBook Pro", acceptsAgentClose: acceptsAgentClose)
        await mac.setWorkspaces([
            LinkWorkspace(
                workspaceId: "ws-shellx", title: "shellx-ios", order: 0, directory: "~/shellx/shellx-ios",
                branch: "feat/workspaces",
                terminals: [
                    LinkTerminal(terminalId: "t-claude", title: "claude", order: 0, selected: false, sessionId: "s1"),
                    LinkTerminal(terminalId: "t-zsh", title: "zsh", order: 1, selected: true),
                ]),
            LinkWorkspace(
                workspaceId: "ws-web", title: "web", order: 1,
                terminals: [LinkTerminal(terminalId: "t-web", title: "zsh", order: 0, selected: true)]),
        ])
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        await mac.upsertSession(
            AgentSession(
                sessionId: "s1", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx-ios", state: .working,
                stateSinceMs: nowMs - 240_000, lastActivityMs: nowMs))
        await mac.setHistory(
            sessionId: "s1",
            entries: [
                ChatEntry(
                    id: "e1", rev: 1, seq: 1, role: .user, kind: .prose, text: "thêm danh sách workspace vào màn chính",
                    tsMs: 1_700_000_000_000),
                ChatEntry(
                    id: "e2", rev: 1, seq: 2, role: .agent, kind: .prose,
                    text: "Mình sẽ thêm **WorkspaceList** và sửa màn chính.", tsMs: 1_700_000_001_000),
            ])
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines([mac.machine], owner: "u1")
        let suite = "WorkspaceRig-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        test.addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-rig-\(UUID().uuidString)", isDirectory: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let relay = FakeRelayAccount()
        let latency = LatencyLog()
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet([mac], phoneKey: { try await vault.phoneKey() }),
            latency: latency, defaults: defaults, sleep: { try await Task.sleep(for: $0) }, onUnauthorized: {})
        test.addTeardownBlock { @MainActor in await hub.stopAll() }
        let scope = AppComposition.makeScope(
            hub: hub, history: ConversationStore(directory: directory), latency: latency,
            launch: LaunchMark(latency: latency), pairing: PairingModel(hub: hub, relay: relay, vault: vault))
        await hub.start()
        let id = mac.machine.machineID
        let ready = await eventually { hub.workspaceRows(machineID: id).count == 2 && hub.liveSessions.count == 1 }
        XCTAssertTrue(ready)

        let model = WorkspaceScreenModel(ref: WorkspaceRef(machineID: id, workspaceId: "ws-\(name)"), hub: hub)
        let screen = Screen()
        let actions = WorkspaceScreenActions.make(
            scope: scope, model: model, alert: { screen.alerts.append($0) }, closing: { screen.closings += 1 },
            done: { screen.tasks.append($0) })
        return WorkspaceRig(scope: scope, model: model, screen: screen, actions: actions, mac: mac)
    }
}
