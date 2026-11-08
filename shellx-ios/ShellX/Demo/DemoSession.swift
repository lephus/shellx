import Observation
import ShellXAppCore

/// "Try without an account": the demo over the real app until Exit. It never calls the relay or the Keychain.
@MainActor @Observable
final class DemoSession {
    private(set) var graph: AppGraph?
    @ObservationIgnored private let make: @MainActor () -> AppGraph

    init(make: @escaping @MainActor () -> AppGraph = { DemoComposition.make(pasteboard: nil) }) {
        self.make = make
    }

    /// No-op while one runs.
    func start() async {
        guard graph == nil else { return }
        let graph = make()
        self.graph = graph
        await graph.prepare()
        await graph.coordinator.launch()
    }

    /// Drops the graph first, so the screens leave, then stops the old graph's script and hub.
    func exit() async {
        guard let old = graph else { return }
        graph = nil
        await old.teardown()
    }
}
