#if DEBUG
import Foundation
import ShellXAppTestSupport

/// Plays `FakeMacDemoScript` on the demo's "Mac giả" for as long as the app runs: two Claude Code
/// sessions with every kind of chat entry and a permission request, a question and a plan waiting,
/// then every 20 s another request in turn, while the sessions switch between working and idle
/// (Debug, `SHELLX_DEMO=1` only).
@MainActor
final class DemoScript {
    private let script: FakeMacDemoScript
    private var task: Task<Void, Never>?

    init(mac: FakeMac) {
        script = FakeMacDemoScript(mac: mac)
    }

    /// Sets the Mac up (sessions and chat are there before the app connects) with one request of
    /// each kind already waiting, then keeps playing.
    func start() async {
        guard task == nil else { return }
        await script.setUp()
        let played = 3
        for index in 0..<played { await script.step(index) }
        let script = self.script
        task = Task.detached {
            await script.run(sleep: { try await Task.sleep(for: $0) }, setUp: false, from: played)
        }
    }
}
#endif
