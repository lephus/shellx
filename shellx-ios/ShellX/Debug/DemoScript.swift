#if DEBUG
import Foundation
import ShellXAppTestSupport

/// Plays `FakeMacDemoScript` on the demo's "Mac giả" for as long as the app runs: two Claude Code
/// sessions with every kind of chat entry, then every 20 s a permission request, a question or a
/// plan in turn, while the sessions switch between working and idle (Debug, `SHELLX_DEMO=1` only).
@MainActor
final class DemoScript {
    private let script: FakeMacDemoScript
    private var task: Task<Void, Never>?

    init(mac: FakeMac) {
        script = FakeMacDemoScript(mac: mac)
    }

    /// Sets the Mac up (sessions and chat are there before the app connects), then keeps playing.
    func start() async {
        guard task == nil else { return }
        await script.setUp()
        let script = self.script
        task = Task.detached {
            await script.run(sleep: { try await Task.sleep(for: $0) }, setUp: false)
        }
    }
}
#endif
