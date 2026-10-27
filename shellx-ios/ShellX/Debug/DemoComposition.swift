#if DEBUG
import Foundation
import ShellXAppCore
import ShellXAppTestSupport
import UIKit

/// The Debug demo (`SHELLX_DEMO=1`, `dev.sh sim --demo`): the app runs without a relay or the
/// Keychain, signed in to a fake account and paired with "Mac giả", an in-process `FakeMac` running
/// `DemoScript`. A second fake Mac, "Mac giả 2", is not paired: its (fake) pairing code is put on
/// the pasteboard, so "Paste Pairing Code" pairs it; the fake relay approves after `approvalDelay`.
@MainActor
enum DemoComposition {
    static let firstName = "Mac giả"
    static let secondName = "Mac giả 2"

    /// `pasteboard` receives the second Mac's code; `runsScript` false keeps the first Mac still
    /// (tests).
    static func make(
        approvalDelay: Duration = .seconds(2), pasteboard: UIPasteboard = .general, runsScript: Bool = true
    ) -> AppGraph {
        let vault = AccountVault(store: InMemorySecretStore())
        let relay = FakeRelayAccount()
        let first = FakeMac(name: firstName)
        let second = FakeMac(name: secondName)
        let connector = FakeMacFleet([first, second], phoneKey: { try await vault.phoneKey() })
        let latency = LatencyLog()
        // Its own defaults, so the demo's default Mac never leaks into a real run.
        let defaults = UserDefaults(suiteName: "com.shellx.dev.demo") ?? .standard
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: "iPhone", wipers: [],
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay, connector: connector, latency: latency, defaults: defaults,
                    sleep: { try await Task.sleep(for: $0) }, onUnauthorized: {})
            })
        let script = DemoScript(mac: first)
        let once = Once()
        return AppGraph(
            coordinator: coordinator,
            makePairing: { PairingModel(hub: $0, relay: relay, vault: vault) },
            prepare: {
                // Seeding again would drop a Mac paired since.
                guard once.first() else { return }
                do {
                    try await vault.setSession(
                        StoredSession(
                            userID: "demo", deviceID: "demo-iphone", token: "demo-token", email: "demo@shellx.pro"))
                    try await vault.setMachines([first.machine], owner: "demo")
                } catch {
                    assertionFailure("the in-memory store does not fail")
                }
                await relay.addGrant(for: first.machine)
                await relay.setApprovalDelay(approvalDelay)
                let code = await second.pairingCode()
                pasteboard.string = code
                if runsScript { await script.start() }
            })
    }
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
#endif
