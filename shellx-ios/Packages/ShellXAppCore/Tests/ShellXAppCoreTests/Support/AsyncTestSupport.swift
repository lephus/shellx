import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// Polls `condition` until it holds or `timeout` passes. Only a wait for an asynchronous effect: no
/// test logic depends on how long it takes.
func eventually(
    timeout: Duration = .seconds(10), isolation: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

/// A `sleep` that returns at once, so reconnect backoff costs nothing.
let instantSleep: @Sendable (Duration) async throws -> Void = { _ in await Task.yield() }

/// A `sleep` the test drives: every call waits until the test releases it, or until its task is
/// cancelled (then it throws `CancellationError`, as `Task.sleep` does).
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: (duration: Duration, continuation: CheckedContinuation<Void, any Error>)] = [:]
    private var calls: [Duration] = []
    private var cancellations = 0

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in try await self.wait(duration) }
    }

    /// Every duration asked for, in order.
    var requested: [Duration] { lock.withLock { calls } }
    /// The durations of the waits still blocked.
    var waiting: [Duration] { lock.withLock { waiters.values.map(\.duration) } }
    /// How many waits ended by cancellation.
    var cancelled: Int { lock.withLock { cancellations } }

    /// Ends every blocked wait whose duration matches, as if the time had passed.
    func release(where matches: (Duration) -> Bool = { _ in true }) {
        let due = lock.withLock {
            let ids = waiters.filter { matches($0.value.duration) }.map(\.key)
            return ids.compactMap { waiters.removeValue(forKey: $0)?.continuation }
        }
        for continuation in due { continuation.resume() }
    }

    private func wait(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                calls.append(duration)
                if Task.isCancelled {
                    cancellations += 1
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[id] = (duration, continuation)
                lock.unlock()
            }
        } onCancel: {
            let waiter = lock.withLock {
                let waiter = waiters.removeValue(forKey: id)
                if waiter != nil { cancellations += 1 }
                return waiter
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }
}

/// Holds callers until the test opens it. Ignores cancellation on purpose, so a test can keep a
/// call (and whoever awaits it) suspended at a known point.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// How many callers are held right now.
    var waiting: Int { lock.withLock { waiters.count } }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let pass = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if pass { continuation.resume() }
        }
    }

    /// Lets every held caller and every later one through.
    func open() {
        let held = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        for continuation in held { continuation.resume() }
    }
}

/// Reads a `MachineConnection`'s events as they come and keeps what tests look at. Chat pushes are
/// only counted, so a flood of them is not kept in memory here either.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stateList: [MachineLinkState] = []
    private var pendingList: [(set: PendingSet, actionable: Bool)] = []
    private var sessionList: [(set: SessionSet, supported: Bool)] = []
    private var chatCount = 0
    private var lastChatSession: String?
    private var signedOutCount = 0
    private var isFinished = false
    private var reader: Task<Void, Never>?

    init(_ events: AsyncStream<MachineEvent>) {
        reader = Task { [self] in
            for await event in events { self.add(event) }
            lock.withLock { isFinished = true }
        }
    }

    var states: [MachineLinkState] { lock.withLock { stateList } }
    var state: MachineLinkState? { states.last }
    var pendingEvents: [(set: PendingSet, actionable: Bool)] { lock.withLock { pendingList } }
    var pending: (set: PendingSet, actionable: Bool)? { pendingEvents.last }
    var pendingIDs: [String] { pending?.set.items.map(\.requestId) ?? [] }
    var sessions: (set: SessionSet, supported: Bool)? { lock.withLock { sessionList.last } }
    var sessionIDs: [String] { sessions?.set.sessions.map(\.sessionId) ?? [] }
    var chatEntries: Int { lock.withLock { chatCount } }
    var signedOut: Int { lock.withLock { signedOutCount } }
    /// True once the connection finished its event stream.
    var finished: Bool { lock.withLock { isFinished } }

    var isOnline: Bool { state == .online }
    var isOffline: Bool {
        if case .offline = state { return true }
        return false
    }

    private func add(_ event: MachineEvent) {
        lock.withLock {
            switch event {
            case let .state(state): stateList.append(state)
            case let .pending(set, actionable): pendingList.append((set, actionable))
            case let .sessions(set, supported): sessionList.append((set, supported))
            case let .chat(sessionId, entries):
                chatCount += entries.count
                lastChatSession = sessionId
            case .signedOut: signedOutCount += 1
            }
        }
    }
}

func pendingItem(_ id: String, createdAtMs: Int64 = 1_700_000_000_000, workspace: String = "shellx") -> PendingItem {
    PendingItem(
        requestId: id, kind: .permission, agent: "claude", workspaceId: "ws-\(workspace)", workspaceTitle: workspace,
        toolName: "Bash", toolInputPreview: "ls", createdAtMs: createdAtMs, modes: ["once", "deny"])
}

func agentSession(
    _ id: String, state: AgentState = .working, lastActivityMs: Int64? = 1_700_000_000_000,
    stateSinceMs: Int64? = 1_700_000_000_000, workspace: String = "shellx"
) -> AgentSession {
    AgentSession(
        sessionId: id, agent: "claude", workspaceId: "ws-\(workspace)", workspaceTitle: workspace, state: state,
        stateSinceMs: stateSinceMs, lastActivityMs: lastActivityMs)
}

func chatEntry(_ seq: Int, text: String? = nil) -> ChatEntry {
    ChatEntry(
        id: "e-\(seq)", rev: 1, seq: seq, role: .agent, kind: .prose, text: text ?? "entry \(seq)",
        tsMs: 1_700_000_000_000 + Int64(seq))
}

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
