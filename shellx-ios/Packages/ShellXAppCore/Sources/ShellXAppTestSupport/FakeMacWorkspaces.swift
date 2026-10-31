import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// `FakeMac`'s workspaces: a `WorkspaceSource` and a `WorkspaceControl` in memory.
///
/// Control acts the way the real Mac does, unless `setNextWorkspaceOutcome(_:)` says otherwise for the next
/// call: a created workspace is added with one terminal, a rename and a close need a workspace the list holds
/// (else `not_found`), and the last workspace is never closed (`refused`). Every change goes out as a
/// `workspace.changed` to the sessions that are open.
///
/// It is also the Mac's `AgentControl`. Closing an agent needs a session the Mac lists that has not ended
/// (else `not_found`), unless `setNextAgentCloseOutcome(_:)` says otherwise for the next call; on `ok` the
/// session turns `.ended` and goes out as a session change, the way the real Mac's liveness sweep reports
/// it once the terminal is gone. `hold()` holds agent closes too.
///
/// And its `TerminalControl`. Closing a terminal needs a terminal the named workspace lists (else `not_found`,
/// which also covers a terminal of another workspace), unless `setNextTerminalCloseOutcome(_:)` says otherwise
/// for the next call; on `ok` the terminal leaves its workspace, which goes with it when it was the last
/// terminal, and the change goes out as a `workspace.changed`, the way the real Mac's list update reports it.
/// Unlike an agent close it looks for no session. `hold()` holds terminal closes too.
final class FakeMacWorkspaces: WorkspaceSource, WorkspaceControl, AgentControl, TerminalControl, @unchecked Sendable {
    typealias Change = (revision: Int, upserted: [LinkWorkspace], removed: [String])

    private let lock = NSLock()
    private var byId: [String: LinkWorkspace] = [:]
    private var revision = 0
    private var subscribers: [UUID: AsyncStream<Change>.Continuation] = [:]
    private var lists = 0
    private var calls: [String] = []
    private var nextOutcome: WorkspaceControlOutcome?
    private var created = 0
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var agentCalls: [String] = []
    private var nextAgentOutcome: WorkspaceControlOutcome?
    private var terminalCalls: [(workspaceId: String, terminalId: String)] = []
    private var nextTerminalOutcome: WorkspaceControlOutcome?
    private let sessions: FakeMacSessions

    /// `sessions` is the Mac's session list, where a closed agent turns `.ended`.
    init(sessions: FakeMacSessions) {
        self.sessions = sessions
    }

    var listCount: Int { lock.withLock { lists } }
    var controlCalls: [String] { lock.withLock { calls } }
    /// The session id of every `agent.close` received, in order.
    var agentCloses: [String] { lock.withLock { agentCalls } }
    /// The workspace id and terminal id of every `terminal.close` received, in order.
    var terminalCloses: [(workspaceId: String, terminalId: String)] { lock.withLock { terminalCalls } }

    /// Replaces the list; what differs from the old one goes out as one change. Nothing differs: no change.
    func set(_ workspaces: [LinkWorkspace]) {
        lock.withLock {
            let new = Dictionary(workspaces.map { ($0.workspaceId, $0) }, uniquingKeysWith: { _, last in last })
            let upserted = Self.sorted(new.values.filter { byId[$0.workspaceId] != $0 })
            let removed = byId.keys.filter { new[$0] == nil }.sorted()
            byId = new
            guard !upserted.isEmpty || !removed.isEmpty else { return }
            broadcastLocked(upserted: upserted, removed: removed)
        }
    }

    func upsert(_ workspace: LinkWorkspace) {
        lock.withLock {
            byId[workspace.workspaceId] = workspace
            broadcastLocked(upserted: [workspace], removed: [])
        }
    }

    func remove(_ workspaceId: String) {
        lock.withLock {
            guard byId.removeValue(forKey: workspaceId) != nil else { return }
            broadcastLocked(upserted: [], removed: [workspaceId])
        }
    }

    /// Raises the revision without telling anyone, so the next change skips one.
    func skipRevision() {
        lock.withLock { revision += 1 }
    }

    /// The next control call answers `outcome` and, unless it is `ok`, changes nothing.
    func setNextOutcome(_ outcome: WorkspaceControlOutcome) {
        lock.withLock { nextOutcome = outcome }
    }

    /// The next `agent.close` answers `outcome` and, unless it is `ok`, changes nothing.
    func setNextAgentCloseOutcome(_ outcome: WorkspaceControlOutcome) {
        lock.withLock { nextAgentOutcome = outcome }
    }

    /// The next `terminal.close` answers `outcome` and, unless it is `ok`, changes nothing.
    func setNextTerminalCloseOutcome(_ outcome: WorkspaceControlOutcome) {
        lock.withLock { nextTerminalOutcome = outcome }
    }

    /// Control calls (workspace, agent and terminal) are recorded, then wait for `release()`.
    func hold() {
        lock.withLock { holding = true }
    }

    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { held = [] }
            return held
        }
        for continuation in waiting { continuation.resume() }
    }

    // MARK: - WorkspaceSource

    func workspaces() async -> (revision: Int, workspaces: [LinkWorkspace]) {
        lock.withLock {
            lists += 1
            return (revision, Self.sorted(byId.values))
        }
    }

    func workspaceChanges() -> AsyncStream<Change> {
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self)
        lock.withLock { subscribers[UUID()] = continuation }
        // No onTermination: a finished subscriber is dropped at the next broadcast, so no lock is ever taken
        // inside the runtime's termination callback.
        return stream
    }

    // MARK: - WorkspaceControl

    func createWorkspace() async -> (outcome: WorkspaceControlOutcome, workspaceId: String?) {
        lock.withLock { calls.append("create") }
        await waitWhileHeld()
        return lock.withLock {
            if let outcome = takeOutcomeLocked(), outcome != .ok { return (outcome, nil) }
            created += 1
            let id = "ws-new-\(created)"
            let workspace = LinkWorkspace(
                workspaceId: id, title: "Workspace \(created)", order: (byId.values.map(\.order).max() ?? -1) + 1,
                terminals: [LinkTerminal(terminalId: "\(id)-t1", title: "zsh", order: 0, selected: true)])
            byId[id] = workspace
            broadcastLocked(upserted: [workspace], removed: [])
            return (.ok, id)
        }
    }

    func renameWorkspace(workspaceId: String, title: String) async -> WorkspaceControlOutcome {
        lock.withLock { calls.append("rename:\(workspaceId):\(title)") }
        await waitWhileHeld()
        return lock.withLock {
            if let outcome = takeOutcomeLocked(), outcome != .ok { return outcome }
            guard var workspace = byId[workspaceId] else { return .notFound }
            workspace.title = title
            byId[workspaceId] = workspace
            broadcastLocked(upserted: [workspace], removed: [])
            return .ok
        }
    }

    func closeWorkspace(workspaceId: String) async -> WorkspaceControlOutcome {
        lock.withLock { calls.append("close:\(workspaceId)") }
        await waitWhileHeld()
        return lock.withLock {
            if let outcome = takeOutcomeLocked(), outcome != .ok { return outcome }
            guard byId[workspaceId] != nil else { return .notFound }
            // The Mac's own rule: it keeps one workspace.
            guard byId.count > 1 else { return .refused }
            byId.removeValue(forKey: workspaceId)
            broadcastLocked(upserted: [], removed: [workspaceId])
            return .ok
        }
    }

    // MARK: - AgentControl

    func closeAgent(sessionId: String) async -> WorkspaceControlOutcome {
        lock.withLock { agentCalls.append(sessionId) }
        await waitWhileHeld()
        let forced = lock.withLock { () -> WorkspaceControlOutcome? in
            defer { nextAgentOutcome = nil }
            return nextAgentOutcome
        }
        if let forced, forced != .ok { return forced }
        guard var session = sessions.session(sessionId), session.state != .ended else { return .notFound }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        session.state = .ended
        session.stateSinceMs = nowMs
        session.lastActivityMs = nowMs
        sessions.upsert(session)
        return .ok
    }

    // MARK: - TerminalControl

    func closeTerminal(workspaceId: String, terminalId: String) async -> WorkspaceControlOutcome {
        lock.withLock { terminalCalls.append((workspaceId, terminalId)) }
        await waitWhileHeld()
        return lock.withLock {
            defer { nextTerminalOutcome = nil }
            if let forced = nextTerminalOutcome, forced != .ok { return forced }
            guard var workspace = byId[workspaceId], workspace.terminals.contains(where: { $0.terminalId == terminalId })
            else { return .notFound }
            workspace.terminals.removeAll { $0.terminalId == terminalId }
            if workspace.terminals.isEmpty {
                byId.removeValue(forKey: workspaceId)
                broadcastLocked(upserted: [], removed: [workspaceId])
            } else {
                byId[workspaceId] = workspace
                broadcastLocked(upserted: [workspace], removed: [])
            }
            return .ok
        }
    }

    // MARK: - Private

    private func takeOutcomeLocked() -> WorkspaceControlOutcome? {
        defer { nextOutcome = nil }
        return nextOutcome
    }

    private func waitWhileHeld() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let pass = lock.withLock { () -> Bool in
                guard holding else { return true }
                held.append(continuation)
                return false
            }
            if pass { continuation.resume() }
        }
    }

    private func broadcastLocked(upserted: [LinkWorkspace], removed: [String]) {
        revision += 1
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield((revision, upserted, removed)) { subscribers[id] = nil }
        }
    }

    private static func sorted(_ workspaces: some Sequence<LinkWorkspace>) -> [LinkWorkspace] {
        workspaces.sorted { ($0.order, $0.workspaceId) < ($1.order, $1.workspaceId) }
    }
}
