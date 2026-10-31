import Foundation
import ShellXLinkCore
import ShellXLinkSession

typealias WorkspaceChange = (revision: Int, upserted: [LinkWorkspace], removed: [String])

/// An in-memory `WorkspaceSource`: a dictionary of workspaces plus a revision counter.
final class FakeWorkspaceSource: WorkspaceSource, @unchecked Sendable {
    private let lock = NSLock()
    private var byId: [String: LinkWorkspace] = [:]
    private var revision = 0
    private var subscribers: [UUID: AsyncStream<WorkspaceChange>.Continuation] = [:]
    private var _listCalls = 0
    private var _changesCalls = 0
    /// Subscribers whose stream has terminated (own lock, see `FakeFeedSource`).
    private let terminationLock = NSLock()
    private var terminated: Set<UUID> = []

    init(_ workspaces: [LinkWorkspace] = []) {
        for workspace in workspaces { byId[workspace.workspaceId] = workspace }
    }

    var listCalls: Int { lock.withLock { _listCalls } }
    var changesCalls: Int { lock.withLock { _changesCalls } }
    var activeSubscribers: Int {
        let ids = lock.withLock { Set(subscribers.keys) }
        return ids.subtracting(terminationLock.withLock { terminated }).count
    }

    func upsert(_ workspaces: LinkWorkspace...) {
        upsert(all: workspaces)
    }

    func upsert(all workspaces: [LinkWorkspace]) {
        lock.withLock {
            for workspace in workspaces { byId[workspace.workspaceId] = workspace }
            broadcastLocked(upserted: workspaces, removed: [])
        }
    }

    func remove(_ workspaceId: String) {
        lock.withLock {
            guard byId.removeValue(forKey: workspaceId) != nil else { return }
            broadcastLocked(upserted: [], removed: [workspaceId])
        }
    }

    func workspaces() async -> (revision: Int, workspaces: [LinkWorkspace]) {
        lock.withLock {
            _listCalls += 1
            return (revision, byId.values.sorted { ($0.order, $0.workspaceId) < ($1.order, $1.workspaceId) })
        }
    }

    func workspaceChanges() -> AsyncStream<WorkspaceChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: WorkspaceChange.self)
        let id = UUID()
        lock.withLock {
            _changesCalls += 1
            subscribers[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.terminationLock.withLock { self.terminated.insert(id) }
        }
        return stream
    }

    private func broadcastLocked(upserted: [LinkWorkspace], removed: [String]) {
        revision += 1
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield((revision, upserted, removed)) {
                subscribers[id] = nil
            }
        }
    }
}

/// A `WorkspaceControl` that logs its calls and answers with the outcomes it is given.
final class FakeWorkspaceControl: WorkspaceControl, @unchecked Sendable {
    enum Call: Equatable {
        case create
        case rename(workspaceId: String, title: String)
        case close(workspaceId: String)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var created: (outcome: WorkspaceControlOutcome, workspaceId: String?) = (.ok, "ws-new")
    private var renamed: WorkspaceControlOutcome = .ok
    private var closed: WorkspaceControlOutcome = .ok
    private var gate: Gate?

    var calls: [Call] { lock.withLock { _calls } }

    func setCreate(_ outcome: WorkspaceControlOutcome, workspaceId: String?) {
        lock.withLock { created = (outcome, workspaceId) }
    }

    func setRename(_ outcome: WorkspaceControlOutcome) { lock.withLock { renamed = outcome } }
    func setClose(_ outcome: WorkspaceControlOutcome) { lock.withLock { closed = outcome } }

    /// Every later call waits for `gate` to open before it answers (after it was logged).
    func hold(until gate: Gate) { lock.withLock { self.gate = gate } }

    func createWorkspace() async -> (outcome: WorkspaceControlOutcome, workspaceId: String?) {
        let (result, gate) = lock.withLock { () -> ((outcome: WorkspaceControlOutcome, workspaceId: String?), Gate?) in
            _calls.append(.create)
            return (created, self.gate)
        }
        await gate?.wait()
        return result
    }

    func renameWorkspace(workspaceId: String, title: String) async -> WorkspaceControlOutcome {
        let (result, gate) = lock.withLock { () -> (WorkspaceControlOutcome, Gate?) in
            _calls.append(.rename(workspaceId: workspaceId, title: title))
            return (renamed, self.gate)
        }
        await gate?.wait()
        return result
    }

    func closeWorkspace(workspaceId: String) async -> WorkspaceControlOutcome {
        let (result, gate) = lock.withLock { () -> (WorkspaceControlOutcome, Gate?) in
            _calls.append(.close(workspaceId: workspaceId))
            return (closed, self.gate)
        }
        await gate?.wait()
        return result
    }
}

/// An `AgentControl` that logs the session ids it is asked to close and answers with the outcome it is given.
final class FakeAgentControl: AgentControl, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var closed: WorkspaceControlOutcome = .ok
    private var gate: Gate?

    var calls: [String] { lock.withLock { _calls } }

    func setClose(_ outcome: WorkspaceControlOutcome) { lock.withLock { closed = outcome } }

    /// Every later call waits for `gate` to open before it answers (after it was logged).
    func hold(until gate: Gate) { lock.withLock { self.gate = gate } }

    func closeAgent(sessionId: String) async -> WorkspaceControlOutcome {
        let (result, gate) = lock.withLock { () -> (WorkspaceControlOutcome, Gate?) in
            _calls.append(sessionId)
            return (closed, self.gate)
        }
        await gate?.wait()
        return result
    }
}

/// A `TerminalControl` that logs the (workspace id, terminal id) pairs it is asked to close and answers with the
/// outcome it is given.
final class FakeTerminalControl: TerminalControl, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(workspaceId: String, terminalId: String)] = []
    private var closed: WorkspaceControlOutcome = .ok
    private var gate: Gate?

    var calls: [(workspaceId: String, terminalId: String)] { lock.withLock { _calls } }

    func setClose(_ outcome: WorkspaceControlOutcome) { lock.withLock { closed = outcome } }

    /// Every later call waits for `gate` to open before it answers (after it was logged).
    func hold(until gate: Gate) { lock.withLock { self.gate = gate } }

    func closeTerminal(workspaceId: String, terminalId: String) async -> WorkspaceControlOutcome {
        let (result, gate) = lock.withLock { () -> (WorkspaceControlOutcome, Gate?) in
            _calls.append((workspaceId, terminalId))
            return (closed, self.gate)
        }
        await gate?.wait()
        return result
    }
}

/// Suspends `wait()` until `open()` is called, for as many waiters as there are.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        for continuation in pending { continuation.resume() }
    }
}

func linkWorkspace(
    _ id: String, title: String = "shellx", order: Int = 0, directory: String? = nil, branch: String? = nil,
    ports: [Int]? = nil, terminals: [LinkTerminal]? = nil
) -> LinkWorkspace {
    LinkWorkspace(
        workspaceId: id, title: title, order: order, directory: directory, branch: branch, ports: ports,
        terminals: terminals ?? [LinkTerminal(terminalId: "t-\(id)", title: "zsh", order: 0, selected: true)])
}
