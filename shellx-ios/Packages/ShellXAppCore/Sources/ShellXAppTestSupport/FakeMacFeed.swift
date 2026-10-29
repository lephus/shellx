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
    private var presetResolves = true
    private var replies: [FakeMac.Decision] = []
    private var snapshots = 0
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    var decisions: [FakeMac.Decision] { lock.withLock { replies } }
    var snapshotCount: Int { lock.withLock { snapshots } }
    var heldSnapshotCount: Int { lock.withLock { held.count } }

    /// Snapshot requests wait (the session stays connected but never syncs) until `releaseSnapshots()`.
    func holdSnapshots() {
        lock.withLock { holding = true }
    }

    func releaseSnapshots() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { held = [] }
            return held
        }
        for continuation in waiting { continuation.resume() }
    }

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

    func setReplyOutcome(_ outcome: ReplyOutcome?, delay: Duration, resolves: Bool) {
        lock.withLock {
            presetOutcome = outcome
            replyDelay = delay
            presetResolves = resolves
        }
    }

    func snapshot() async -> (revision: Int, pending: [PendingItem]) {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let pass = lock.withLock { () -> Bool in
                guard holding else { return true }
                held.append(continuation)
                return false
            }
            if pass { continuation.resume() }
        }
        return lock.withLock {
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
        let (preset, delay, resolves) = lock.withLock {
            replies.append(FakeMac.Decision(requestId: requestId, decision: decision))
            return (presetOutcome, replyDelay, presetResolves)
        }
        if delay > .zero { try? await Task.sleep(for: delay) }
        return lock.withLock {
            if let preset {
                if preset == .delivered, resolves { resolveLocked(requestId) }
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
