import Foundation
import ShellXAppCore
import ShellXDemo
import UIKit

/// The demo ("Try without an account" in every build, and `SHELLX_DEMO=1` / `dev.sh sim --demo` in Debug): the app runs
/// without a relay or the Keychain, signed in to a fake account and paired with "Mac giả", an in-process `FakeMac` running
/// `DemoScript`. A second fake Mac, "Mac giả 2", is not paired: when `pasteboard` is given its (fake) pairing code is put
/// there, so "Paste Pairing Code" pairs it; the demo relay approves after `approvalDelay`.
///
/// The agents' chat copies are kept in `Application Support/ShellXDemo`, apart from a real run's, and
/// the fake Macs keep fixed ids, so they survive a relaunch of the demo.
@MainActor
enum DemoComposition {
    static let firstName = "Mac giả"
    static let secondName = "Mac giả 2"
    static let defaultHistory = URL.applicationSupportDirectory.appendingPathComponent("ShellXDemo", isDirectory: true)

    /// `pasteboard` receives the second Mac's code; `runsScript` false keeps the first Mac still
    /// (tests); `history` holds the agents' chat copies.
    static func make(
        approvalDelay: Duration = .seconds(2), pasteboard: UIPasteboard? = .general, runsScript: Bool = true,
        history historyDirectory: URL = defaultHistory
    ) -> AppGraph {
        let vault = AccountVault(store: DemoSecretStore())
        let first = FakeMac(name: firstName, id: "demo-1")
        let second = FakeMac(name: secondName, id: "demo-2")
        let relay = DemoRelay(
            paired: [first.machine], pairableMachineIDs: [second.machine.machineID], approvalDelay: approvalDelay)
        let connector = FakeMacFleet([first, second], phoneKey: { try await vault.phoneKey() })
        let latency = LatencyLog()
        let launch = LaunchMark(latency: latency)
        let scopes = SignedInScope.Slot()
        // Its own defaults, so the demo's default Mac never leaks into a real run.
        let defaults = UserDefaults(suiteName: "com.shellx.dev.demo") ?? .standard
        AppComposition.removeMergedChatData(in: historyDirectory, defaults: defaults)
        let history = ConversationStore(directory: historyDirectory)
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: "iPhone", wipers: [history],
            makeHub: {
                let hub = MachineHub(
                    vault: vault, relay: relay, connector: connector, latency: latency, defaults: defaults,
                    sleep: { try await Task.sleep(for: $0) }, onUnauthorized: {})
                // Real speech recognition, so the demo measures the mic on an iPhone.
                scopes.current = AppComposition.makeScope(
                    hub: hub, history: history, latency: latency, launch: launch,
                    pairing: PairingModel(hub: hub, relay: relay, vault: vault), defaults: defaults,
                    voice: VoiceService.system(latency: latency, defaults: defaults, hub: hub))
                return hub
            })
        let script = DemoScript(mac: first)
        let once = Once()
        return AppGraph(
            coordinator: coordinator,
            scopes: scopes,
            launch: launch,
            prepare: {
                // Seeding again would drop a Mac paired since.
                guard once.first() else { return }
                do {
                    try await vault.setSession(
                        StoredSession(
                            userID: "demo", deviceID: "demo-iphone", token: "demo-token", email: "demo@shellx.pro", authMethod: .google))
                    try await vault.setMachines([first.machine], owner: "demo")
                } catch {
                    assertionFailure("the in-memory store does not fail")
                }
                let code = await second.pairingCode()
                pasteboard?.string = code
                if runsScript {
                    await script.start()
                    // The Mac's sidebar as the design shows it, over the script's two sessions.
                    await first.setWorkspaces(Self.workspaces)
                }
            },
            teardown: {
                await script.stop()
                await coordinator.hub?.stopAll()
            })
    }

    /// "Mac giả" has four workspaces: `shellx-ios` and `web` hold the script's two Claude Code sessions
    /// (their ids are the ones the sessions and requests carry), `relay` a dev server and `notes` a shell.
    static let workspaces: [LinkWorkspace] = [
        LinkWorkspace(
            workspaceId: "ws-shellx", title: "shellx-ios", order: 0, directory: "~/shellx/shellx-ios",
            branch: "feat/workspaces",
            terminals: [
                LinkTerminal(terminalId: "demo-shellx-t1", title: "claude", order: 0, selected: true, sessionId: "demo-shellx"),
                LinkTerminal(terminalId: "demo-shellx-t2", title: "zsh", order: 1, selected: false),
            ]),
        LinkWorkspace(
            workspaceId: "ws-relay", title: "relay", order: 1, directory: "~/shellx/relay", branch: "main",
            ports: [8787], terminals: [LinkTerminal(terminalId: "demo-relay-t1", title: "npm", order: 0, selected: true)]),
        LinkWorkspace(
            workspaceId: "ws-web", title: "web", order: 2, directory: "~/shellx/web", branch: "develop", ports: [3000],
            terminals: [
                LinkTerminal(terminalId: "demo-web-t1", title: "claude", order: 0, selected: true, sessionId: "demo-web")
            ]),
        LinkWorkspace(
            workspaceId: "ws-notes", title: "notes", order: 3, directory: "~",
            terminals: [LinkTerminal(terminalId: "demo-notes-t1", title: "zsh", order: 0, selected: true)]),
    ]
}

/// True on the first call only.
@MainActor
private final class Once {
    private var done = false

    func first() -> Bool {
        defer { done = true }
        return !done
    }
}
