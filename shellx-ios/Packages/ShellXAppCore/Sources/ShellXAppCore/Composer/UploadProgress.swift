import Foundation
import Observation

/// How far the attachments of the message being sent got, for the screen that sends it: the bytes
/// uploaded over the bytes to upload, nil while no upload runs. Values come from the Link client's
/// actor and are applied on the main actor, only while their send is the latest one, and only
/// upward.
@MainActor @Observable
final class UploadProgress {
    private(set) var fraction: Double?
    @ObservationIgnored private var run = 0

    /// Runs `send` with a progress callback to hand to `MachineHub.chatSend`: `fraction` is 0 from
    /// now, follows the callback, and is nil again when `send` returns or throws.
    func track<T>(_ send: (_ progress: @escaping @Sendable (Double) -> Void) async throws -> T) async throws -> T {
        run += 1
        let current = run
        fraction = 0
        defer { if run == current { fraction = nil } }
        return try await send { [weak self] value in
            Task { @MainActor in self?.advance(to: value, in: current) }
        }
    }

    private func advance(to value: Double, in send: Int) {
        // A late value of a send that is over (nil) or replaced does nothing.
        guard send == run, let fraction, value > fraction else { return }
        self.fraction = min(value, 1)
    }
}
