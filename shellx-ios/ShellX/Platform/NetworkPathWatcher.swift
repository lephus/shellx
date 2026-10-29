import Foundation
import Network
import ShellXAppCore

/// Tells the app when the network path changes (Wi-Fi to cellular, another Wi-Fi, back online),
/// so Link sessions that may have died with the old path are replaced at once.
///
/// Only reads `NWPathMonitor`; what counts as a change, and the 300 ms settling, is
/// `NetworkChangeFilter` in ShellXAppCore.
@MainActor
final class NetworkPathWatcher {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.shellx.network-path")
    private var filter: NetworkChangeFilter?

    /// Starts watching; `onChange` runs on the main actor. Calling it again does nothing.
    func start(onChange: @escaping @MainActor () -> Void) {
        guard filter == nil else { return }
        let filter = NetworkChangeFilter(sleep: { try await Task.sleep(for: $0) }, onChange: onChange)
        self.filter = filter
        monitor.pathUpdateHandler = { path in
            // Built on the monitor's queue; only plain values cross to the main actor.
            let snapshot = NetworkPath(
                status: String(describing: path.status),
                interfaces: path.availableInterfaces.map { "\($0.type):\($0.name)" },
                gateways: path.gateways.map { String(describing: $0) })
            Task { @MainActor in filter.receive(snapshot) }
        }
        monitor.start(queue: queue)
    }
}
