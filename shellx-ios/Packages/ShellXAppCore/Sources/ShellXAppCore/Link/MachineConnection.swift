import Foundation
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkSession
import os

/// The Link to one paired Mac: one live session at a time, kept in sync, and brought back when it
/// drops.
///
/// One round: connect, `snapshot()`, `sessions()` (a Mac without a session list answers
/// `unsupported`, which is not a failure), `workspaces()` (only when the Mac lists the `workspaces`
/// feature), report the client's `hostFeatures` and `.online`, then read `changes`,
/// `sessionChanges`, `workspaceChanges` and `chatEntries` until `changes` ends. A revision gap
/// resyncs inside the live session. When the session ends the items stay but are reported not
/// actionable (`.reconnecting`); when the first attempt after that fails they are dropped
/// (`.offline`). Waits follow `ReconnectSchedule`; the failure count starts over at every `welcome`.
/// A refused token (`.signedOut` event), a revoked grant, a changed host key and a protocol
/// mismatch stop the loop for good and finish `events`.
public actor MachineConnection {
    /// Every state and data change, in order. Single consumer; it finishes when the loop stops.
    public nonisolated let events: AsyncStream<MachineEvent>
    private nonisolated let output: AsyncStream<MachineEvent>.Continuation

    private let machine: PairedMachine
    private let connector: any MachineLinkConnecting
    private let latency: LatencyLog
    private let schedule: ReconnectSchedule
    private let sleep: @Sendable (Duration) async throws -> Void
    private let log = Logger(subsystem: "com.shellx.app", category: "link")

    private var state: MachineLinkState = .connecting
    private var pending = PendingSet()
    private var sessions = SessionSet()
    private var sessionsSupported = true
    private var workspaces = WorkspaceSet()
    private var workspacesSupported = false
    /// The client of the current round, from `connect` until the round is over.
    private var client: LinkClient?
    private var loop: Task<Void, Never>?
    private var backoffWait: Task<Void, Never>?
    /// Set by `reconnectNow()` / `forceReconnect()` when no wait is running: the next wait is skipped.
    private var skipBackoff = false
    /// Set by `forceReconnect()` when it closes the client: the round's end is ours, not a failure.
    private var forcedClose = false
    /// Failures in a row since the last `welcome`; a session that ended counts as one.
    private var failures = 0
    /// When the last live session ended: what `.offline(since:)` reports.
    private var lostAt: Date?
    /// True once `stop()` ran or the loop stopped for good.
    private var ended = false

    public init(
        machine: PairedMachine, connector: any MachineLinkConnecting, latency: LatencyLog,
        schedule: ReconnectSchedule = .standard, sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        (events, output) = AsyncStream.makeStream(of: MachineEvent.self)
        self.machine = machine
        self.connector = connector
        self.latency = latency
        self.schedule = schedule
        self.sleep = sleep
    }

    /// Starts the loop. Calling it again, or after `stop()`, does nothing.
    public func start() {
        guard loop == nil, !ended else { return }
        output.yield(.state(.connecting))
        loop = Task { await self.run() }
    }

    /// Stops the loop, closes the live session and finishes `events`.
    public func stop() async {
        ended = true
        loop?.cancel()
        backoffWait?.cancel()
        if let client { await client.close() }
        await loop?.value
        output.finish()
    }

    /// Skips the rest of the current wait (or the next one, when an attempt is under way).
    public func reconnectNow() {
        guard !ended, state != .online else { return }
        if let backoffWait {
            backoffWait.cancel()
        } else {
            skipBackoff = true
        }
    }

    /// Closes the current client and connects again at once: after a network change the session (or
    /// the attempt still syncing) may ride a dead path without either side knowing yet. Dropping it
    /// is not a failure: no backoff, and the items are not cleared. Without a client it is
    /// `reconnectNow()`.
    public func forceReconnect() async {
        guard !ended else { return }
        guard let client else { return reconnectNow() }
        forcedClose = true
        skipBackoff = true
        await client.close()
    }

    /// Runs `body` on the live session. Throws `LinkCallError.offline` (and sends nothing) unless the
    /// Mac is `.online`; errors of `body` itself (`LinkClientError`) pass through.
    public func call<T: Sendable>(_ body: @Sendable (LinkClient) async throws -> T) async throws -> T {
        guard state == .online, let client else { throw LinkCallError.offline(machineName: machine.name) }
        return try await body(client)
    }

    // MARK: - Loop

    private func run() async {
        while !Task.isCancelled {
            do {
                let client = try await connector.connect(machine)
                self.client = client
                // `welcome` arrived: the failure count starts over.
                failures = 0
                try Task.checkCancellation()
                try await establish(client)
                await read(client)
                await client.close()
                self.client = nil
                forcedClose = false
                guard !Task.isCancelled else { break }
                sessionEnded()
            } catch {
                await closeClient()
                guard !Task.isCancelled else { break }
                if forcedClose {
                    // `forceReconnect()` dropped an attempt still syncing: start over at once.
                    forcedClose = false
                } else {
                    guard keepTrying(after: error) else { break }
                }
            }
            await waitBeforeRetry()
        }
        await closeClient()
        ended = true
        output.finish()
    }

    private func closeClient() async {
        guard let client else { return }
        self.client = nil
        await client.close()
    }

    private func establish(_ client: LinkClient) async throws {
        let snapshot = try await client.snapshot()
        let list: (revision: Int, sessions: [AgentSession])?
        do {
            list = try await client.sessions()
        } catch LinkClientError.remote(code: "unsupported", message: _) {
            list = nil
        }
        let workspaceList = try await workspaceList(of: client)
        pending.reset(revision: snapshot.revision, items: snapshot.pending)
        sessions.reset(revision: list?.revision ?? 0, sessions: list?.sessions ?? [])
        sessionsSupported = list != nil
        workspaces.reset(revision: workspaceList?.revision ?? 0, workspaces: workspaceList?.workspaces ?? [])
        workspacesSupported = workspaceList != nil
        lostAt = nil
        skipBackoff = false
        state = .online
        output.yield(.pending(pending, actionable: true))
        output.yield(.sessions(sessions, supported: sessionsSupported))
        output.yield(.workspaces(workspaces, supported: workspacesSupported))
        output.yield(.features(client.hostFeatures))
        output.yield(.state(.online))
    }

    /// The Mac's workspace list, or nil when it has none to give: it did not list the `workspaces`
    /// feature, or it listed it and answered with an error (`unsupported`, `too_large`). Either way
    /// the session stays: it carries the requests the user has to answer. A timeout or a closed
    /// session still ends the round.
    private func workspaceList(of client: LinkClient) async throws -> (revision: Int, workspaces: [LinkWorkspace])? {
        guard client.hostFeatures.contains(ShellXLink.workspacesFeature) else { return nil }
        do {
            return try await client.workspaces()
        } catch LinkClientError.remote(code: _, message: _) {
            log.info("link_workspaces_unavailable")
            return nil
        }
    }

    /// Reads the session's four streams until `changes` ends (the session is over).
    private func read(_ client: LinkClient) async {
        let output = self.output
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await change in client.sessionChanges { await self.applySessions(change, from: client) }
            }
            group.addTask {
                for await change in client.workspaceChanges { await self.applyWorkspaces(change, from: client) }
            }
            group.addTask {
                // Read even when no screen shows chat: the client buffers without bound. A reset
                // stays in order with the entries around it.
                for await push in client.chatEntries {
                    switch push {
                    case let .upsert(sessionId, entries):
                        output.yield(.chat(sessionId: sessionId, entries: entries))
                    case let .reset(sessionId):
                        output.yield(.chatReset(sessionId: sessionId))
                    }
                }
            }
            for await change in client.changes { await applyPending(change, from: client) }
            group.cancelAll()
        }
    }

    private func applyPending(
        _ change: (revision: Int, added: [PendingItem], resolved: [String]), from client: LinkClient
    ) async {
        switch pending.apply(revision: change.revision, added: change.added, resolved: change.resolved) {
        case .applied:
            let now = Self.nowMs()
            for item in change.added { latency.record(.pendingArrival, .milliseconds(now - item.createdAtMs)) }
            output.yield(.pending(pending, actionable: state == .online))
        case .ignored:
            break
        case .gap:
            do {
                let snapshot = try await client.snapshot()
                pending.reset(revision: snapshot.revision, items: snapshot.pending)
                output.yield(.pending(pending, actionable: state == .online))
            } catch {
                // Cannot resync here: end the session, so the next round starts from a snapshot.
                log.info("link_resync_failed")
                await client.close()
            }
        }
    }

    private func applySessions(
        _ change: (revision: Int, upserted: [AgentSession], removed: [String]), from client: LinkClient
    ) async {
        let before = sessions
        switch sessions.apply(revision: change.revision, upserted: change.upserted, removed: change.removed) {
        case .applied:
            let now = Self.nowMs()
            for session in change.upserted where before.session(session.sessionId)?.state != session.state {
                guard let since = session.stateSinceMs else { continue }
                latency.record(.sessionChangeArrival, .milliseconds(now - since))
            }
            output.yield(.sessions(sessions, supported: sessionsSupported))
        case .ignored:
            break
        case .gap:
            do {
                let list = try await client.sessions()
                sessions.reset(revision: list.revision, sessions: list.sessions)
                output.yield(.sessions(sessions, supported: sessionsSupported))
            } catch {
                log.info("link_resync_failed")
                await client.close()
            }
        }
    }

    private func applyWorkspaces(
        _ change: (revision: Int, upserted: [LinkWorkspace], removed: [String]), from client: LinkClient
    ) async {
        switch workspaces.apply(revision: change.revision, upserted: change.upserted, removed: change.removed) {
        case .applied:
            output.yield(.workspaces(workspaces, supported: workspacesSupported))
        case .ignored:
            break
        case .gap:
            do {
                let list = try await client.workspaces()
                workspaces.reset(revision: list.revision, workspaces: list.workspaces)
                output.yield(.workspaces(workspaces, supported: workspacesSupported))
            } catch {
                log.info("link_resync_failed")
                await client.close()
            }
        }
    }

    private func sessionEnded() {
        lostAt = Date()
        failures = 1
        state = .reconnecting
        output.yield(.pending(pending, actionable: false))
        output.yield(.state(.reconnecting))
    }

    /// Records a failed round. Returns false when the loop must stop.
    private func keepTrying(after error: any Error) -> Bool {
        let failure = LinkFailure(error)
        switch failure {
        case .offline:
            log.info("link_attempt_failed")
            failures += 1
            if case .offline = state { return true }
            // Nothing is synced any more: drop the items.
            pending.reset(revision: 0, items: [])
            state = .offline(since: lostAt ?? Date())
            output.yield(.pending(pending, actionable: false))
            output.yield(.state(state))
            return true
        case .signedOut:
            log.notice("link_stopped signed_out")
            pending.reset(revision: 0, items: [])
            state = .offline(since: lostAt ?? Date())
            output.yield(.pending(pending, actionable: false))
            output.yield(.state(state))
            output.yield(.signedOut)
            return false
        case .revoked:
            return stopFor(.revoked)
        case .hostKeyChanged:
            return stopFor(.hostKeyChanged)
        case .needsUpdate:
            return stopFor(.needsUpdate)
        }
    }

    /// Ends in a terminal state: nothing from this Mac can be trusted or synced any more.
    private func stopFor(_ final: MachineLinkState) -> Bool {
        log.notice("link_stopped \(String(describing: final), privacy: .public)")
        pending.reset(revision: 0, items: [])
        sessions.reset(revision: 0, sessions: [])
        workspaces.reset(revision: 0, workspaces: [])
        state = final
        output.yield(.pending(pending, actionable: false))
        output.yield(.sessions(sessions, supported: sessionsSupported))
        output.yield(.workspaces(workspaces, supported: workspacesSupported))
        output.yield(.state(final))
        return false
    }

    private func waitBeforeRetry() async {
        guard !Task.isCancelled else { return }
        if skipBackoff {
            skipBackoff = false
            return
        }
        let delay = schedule.delay(afterFailures: failures, jitter: .random(in: -1...1))
        let sleep = self.sleep
        let wait = Task { _ = try? await sleep(delay) }
        backoffWait = wait
        await withTaskCancellationHandler {
            await wait.value
        } onCancel: {
            wait.cancel()
        }
        backoffWait = nil
    }

    private static func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
