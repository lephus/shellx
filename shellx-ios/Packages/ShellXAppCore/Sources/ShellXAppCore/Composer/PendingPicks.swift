import Foundation
import Observation

/// The photos and files picked for the composer that are still being read. Each holds a place in the
/// composer's row from the moment the picker closes until its read ends; then `done` gets its
/// attachment, or why it could not be read. The composer holds Send while any is left, so a message
/// goes out with every attachment the user kept.
///
/// Any pick can be cancelled (its ✕): its place goes at once and its read's task is cancelled.
/// Whatever that read returns afterwards is dropped, so a read that never ends (an iCloud download
/// that stalls, say) costs one tap, never the whole composer.
///
/// Reads run one at a time, in the order picked, so the attachments arrive in that order and a name
/// made from what the composer already holds (`photo-2.jpg` after `photo-1.jpg`) stays unique.
@MainActor @Observable
public final class PendingPicks {
    public typealias Load = @MainActor () async throws -> OutgoingAttachment
    public typealias Done = @MainActor (Result<OutgoingAttachment, any Error>) -> Void

    /// The picks still being read, in the order picked: the first one is being read now.
    public private(set) var ids: [UUID] = []

    public var count: Int { ids.count }

    private struct Pick {
        let load: Load
        let done: Done
        var task: Task<Void, Never>?
    }

    @ObservationIgnored private var picks: [UUID: Pick] = [:]

    public init() {}

    /// Reads `loads` after the picks already waiting, one at a time and in order, handing each
    /// result to `done`. Returns the picks' ids, in the same order, for `cancel(_:)`.
    @discardableResult
    public func read(_ loads: [Load], done: @escaping Done) -> [UUID] {
        let added = loads.map { load -> UUID in
            let id = UUID()
            picks[id] = Pick(load: load, done: done)
            return id
        }
        ids.append(contentsOf: added)
        startNext()
        return added
    }

    /// Drops pick `id` now: it leaves `ids`, its read's task is cancelled, and `done` never hears of
    /// it. The next pick starts if this one was being read. Nothing happens for an id no longer here.
    public func cancel(_ id: UUID) {
        guard let pick = picks.removeValue(forKey: id) else { return }
        ids.removeAll { $0 == id }
        pick.task?.cancel()
        startNext()
    }

    /// Starts reading the first pick, unless it already runs.
    private func startNext() {
        guard let id = ids.first, var pick = picks[id], pick.task == nil else { return }
        let load = pick.load
        pick.task = Task { [weak self] in
            let result: Result<OutgoingAttachment, any Error>
            do {
                result = .success(try await load())
            } catch {
                result = .failure(error)
            }
            self?.finish(id, with: result)
        }
        picks[id] = pick
    }

    /// The read of pick `id` ended. A pick cancelled meanwhile is gone, and its result with it.
    private func finish(_ id: UUID, with result: Result<OutgoingAttachment, any Error>) {
        guard let pick = picks.removeValue(forKey: id) else { return }
        ids.removeAll { $0 == id }
        pick.done(result)
        startNext()
    }
}
