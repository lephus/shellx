import Foundation

/// Turns the stream of network paths into "the path changed" calls: the first path is the
/// baseline, an equal path is no change, and changes less than `settle` apart are reported once,
/// after the last of them.
@MainActor
public final class NetworkChangeFilter {
    public static let settle: Duration = .milliseconds(300)

    private let sleep: @Sendable (Duration) async throws -> Void
    private let onChange: @MainActor () -> Void
    private var last: NetworkPath?
    private var pending: Task<Void, Never>?

    public init(sleep: @escaping @Sendable (Duration) async throws -> Void, onChange: @escaping @MainActor () -> Void) {
        self.sleep = sleep
        self.onChange = onChange
    }

    public func receive(_ path: NetworkPath) {
        guard path != last else { return }
        let first = last == nil
        last = path
        guard !first else { return }
        pending?.cancel()
        let sleep = self.sleep
        pending = Task { [weak self] in
            do {
                try await sleep(Self.settle)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
