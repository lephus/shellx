import Foundation
import Network

/// Tells the app when the network path changes (Wi-Fi to cellular, another Wi-Fi, back online),
/// so live Link sessions that may have died with the old path are replaced at once.
///
/// A change is a new status, a new set of interfaces or new gateways (switching Wi-Fi networks
/// keeps `en0` but changes the gateway). The first path is the starting point, not a change.
/// Changes less than 300 ms apart are reported once, after the last of them.
@MainActor
final class NetworkPathWatcher {
    private static let settle: Duration = .milliseconds(300)

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.shellx.network-path")
    private var last: PathSignature?
    private var pending: Task<Void, Never>?
    private var onChange: (@MainActor () -> Void)?

    /// Starts watching; `onChange` runs on the main actor. Calling it again does nothing.
    func start(onChange: @escaping @MainActor () -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = PathSignature(path)
            Task { @MainActor in self?.receive(signature) }
        }
        monitor.start(queue: queue)
    }

    private func receive(_ signature: PathSignature) {
        guard signature != last else { return }
        let first = last == nil
        last = signature
        guard !first else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}

/// What about a path counts as a change. Built on the monitor's queue; holds only plain values.
private struct PathSignature: Equatable, Sendable {
    var status: String
    var interfaces: [String]
    var gateways: [String]

    init(_ path: NWPath) {
        status = String(describing: path.status)
        interfaces = path.availableInterfaces.map { "\($0.type):\($0.name)" }
        gateways = path.gateways.map { String(describing: $0) }.sorted()
    }
}
