import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// `FakeMac`'s pending requests: an `AgentFeedSource` in memory.
final class FakeMacFeed: AgentFeedSource, @unchecked Sendable {
    typealias Change = (revision: Int, added: [PendingItem], resolved: [String])

    private let lock = NSLock()
    private var items: [String: PendingItem] = [:]
    private var resolved: Set<String> = []
    private var revision = 0
    private var subscribers: [UUID: AsyncStream<Change>.Continuation] = [:]
    private var presetOutcome: ReplyOutcome?
    private var replyDelay: Duration = .zero
    private var replies: [FakeMac.Decision] = []
    private var snapshots = 0

    var decisions: [FakeMac.Decision] { lock.withLock { replies } }
    var snapshotCount: Int { lock.withLock { snapshots } }

    func add(_ item: PendingItem) {
        lock.withLock {
            items[item.requestId] = item
            broadcastLocked(added: [item], resolved: [])
        }
    }

    func resolve(_ requestId: String) {
        lock.withLock { resolveLocked(requestId) }
    }

    /// Raises the revision without telling anyone, so the next change skips one.
    func skipRevision() {
        lock.withLock { revision += 1 }
    }

    func setReplyOutcome(_ outcome: ReplyOutcome?, delay: Duration) {
        lock.withLock {
            presetOutcome = outcome
            replyDelay = delay
        }
    }

    func snapshot() async -> (revision: Int, pending: [PendingItem]) {
        lock.withLock {
            snapshots += 1
            return (revision, items.values.sorted { $0.requestId < $1.requestId })
        }
    }

    func changes() -> AsyncStream<Change> {
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self)
        lock.withLock { subscribers[UUID()] = continuation }
        // No onTermination: a finished subscriber is dropped at the next broadcast, so no lock is
        // ever taken inside the runtime's termination callback.
        return stream
    }

    func reply(requestId: String, decision: LinkDecision) async -> ReplyOutcome {
        let (preset, delay) = lock.withLock {
            replies.append(FakeMac.Decision(requestId: requestId, decision: decision))
            return (presetOutcome, replyDelay)
        }
        if delay > .zero { try? await Task.sleep(for: delay) }
        return lock.withLock {
            if let preset {
                if preset == .delivered { resolveLocked(requestId) }
                return preset
            }
            if items[requestId] != nil {
                resolveLocked(requestId)
                return .delivered
            }
            return resolved.contains(requestId) ? .alreadyHandled : .unknown
        }
    }

    private func resolveLocked(_ requestId: String) {
        guard items.removeValue(forKey: requestId) != nil else { return }
        resolved.insert(requestId)
        broadcastLocked(added: [], resolved: [requestId])
    }

    private func broadcastLocked(added: [PendingItem], resolved: [String]) {
        revision += 1
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield((revision, added, resolved)) { subscribers[id] = nil }
        }
    }
}
