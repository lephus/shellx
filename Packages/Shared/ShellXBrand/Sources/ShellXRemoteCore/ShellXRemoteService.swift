import Combine
import Foundation
import os

/// K4: the Mac remote seam the sidebar binds to (W2 plan Task 13, Ruling R28).
///
/// * **Host** (this Mac serving): `machines.register` → first `tickets.mint` (relay route) → bridge server →
///   `ShellXDaemonSupervisor`; heartbeat every 30 s; `pair.pending` every 5 s feeds `pendingApprovals`.
/// * **On-site approval** (D9): `approve` refuses a suspicious request before anything runs, then mints a
///   connect ticket to this machine (D3), creates a 300 s enrollment invitation, seals it to the requester
///   through `pair.approve` (passing the fingerprint the person saw) and lets the daemon admit only that
///   invitation id; every other pending enrollment is denied.
/// * **Viewer**: `requestAccess` → `pair.request`, then `pair.poll` every 2 s for up to 300 s; on approval the
///   link record is saved and a `ShellXClientLinkSupervisor` enrolls with the invite file. `openSession` waits
///   for the link, finds or creates a remote terminal and opens a local workspace running the attach wrapper.
///
/// Core calls run on a global queue and cmux-tui runs in detached tasks or the supervisors' actors; only
/// `@Published` state lives on the main actor. Signed-out answers (`not_logged_in`, `unauthorized`,
/// `http_401`) end the session; network and server errors never do (the last machines stay, timers keep going).
/// Logs carry ids, codes and counts only: never a ticket, invite, password or token.
@MainActor
public final class ShellXRemoteService: ObservableObject {
    nonisolated static let heartbeatInterval: TimeInterval = 30
    nonisolated static let machinesInterval: TimeInterval = 15
    nonisolated static let pendingInterval: TimeInterval = 5
    nonisolated static let pollInterval: TimeInterval = 2
    nonisolated static let enrollPollInterval: TimeInterval = 1
    /// Pairings, invitations and shown requests all live 300 s.
    nonisolated static let pairingLifetime: TimeInterval = 300
    nonisolated static let connectTimeout: TimeInterval = 20
    /// `stopForTermination` waits at most this long for links and daemon to stop.
    nonisolated static let terminationBudget: TimeInterval = 1.5
    nonisolated static let inviteTicketName = "invite-connect.ticket"
    nonisolated static let sessionWorkspaceName = "ShellX"

    /// Other machines of the account (never this one).
    @Published public internal(set) var machines: [RemoteMachine] = []
    /// Requests to view and control this Mac, oldest first.
    @Published public internal(set) var pendingApprovals: [PairingRequest] = []
    /// Requests this Mac made.
    @Published public internal(set) var outgoing: [OutgoingPairing] = []
    /// This Mac serving (its daemon).
    @Published public internal(set) var hostState: LinkState = .idle
    @Published public internal(set) var isSignedIn = false
    /// Local workspaces showing a remote terminal, by machine.
    @Published public internal(set) var remoteWorkspaces: [UUID: RemoteMachine.ID] = [:]

    let env: ShellXRemoteEnvironment
    let refresher: ShellXTicketRefresher

    var started = false
    var terminated = false
    var cmuxTuiAvailable = false
    /// The launch sweep and cmux-tui check, run once and shared by `bootstrap` and `signIn`.
    var preparation: Task<Bool, Never>?
    var configuration: Task<Void, any Error>?
    var bootTask: Task<Void, Never>?
    /// Stops of the last session; a new host start waits for them (they stop the bridge).
    var teardown: Task<Void, Never>?
    /// Bumped when a session starts or ends; work begun in another generation drops its result.
    var generation = 0
    /// Every task of the current session by role (timers, host, polls, link consumers).
    var tasks: [String: Task<Void, Never>] = [:]

    var listed: [MachineListReply.Item] = []
    var thisMachineID: RemoteMachine.ID?
    var hostSlot: String?
    var hostRoute: String?
    var daemon: ShellXDaemonSupervisor?
    var clients: [RemoteMachine.ID: ShellXClientLinkSupervisor] = [:]
    var linkStates: [RemoteMachine.ID: LinkState] = [:]
    var records: [RemoteMachine.ID: RemoteLinkRecord] = [:]
    var gate = ApprovalGate()
    /// Approved, denied or expired here: a lagging `pair.pending` never shows them again.
    var handledPairings: Set<PairingRequest.ID> = []
    /// Every request as first shown (sticky `suspicious`, original `firstSeen`) until its 300 s are up, even
    /// while the server leaves it out of a poll.
    var pairingMemory: [PairingRequest.ID: PairingRequest] = [:]
    var approving: Set<PairingRequest.ID> = []
    var requesting: Set<RemoteMachine.ID> = []
    var connectWaiters: [RemoteMachine.ID: [UUID: CheckedContinuation<Bool, Never>]] = [:]

    public init(environment: ShellXRemoteEnvironment) {
        env = environment
        refresher = ShellXTicketRefresher(core: environment.core, clock: environment.clock)
    }

    // MARK: - App lifecycle

    /// Gate off: returns without any process or core call. Gate on: sweeps stale invites, configures the
    /// core, finds out whether a session exists and, if so, starts the host and the timers.
    public func startIfEnabled() {
        guard !started, !terminated, env.gateEnabled() else { return }
        started = true
        bootTask = Task { [weak self] in await self?.bootstrap() }
    }

    /// Synchronous and bounded (`terminationBudget`), even when a cmux-tui run hangs: cancels the timers,
    /// stops the client links and the daemon (`server stop`), then the bridge.
    public func stopForTermination() {
        guard !terminated else { return }
        terminated = true
        guard started || isSignedIn || teardown != nil else { return }   // a sign-out's stops may still run
        generation += 1
        bootTask?.cancel()
        cancelAllTasks()
        resumeAllWaiters(connected: false)
        gate = ApprovalGate()
        pairingMemory = [:]
        let clients = Array(self.clients.values), daemon = self.daemon, bridge = env.bridge, teardown = self.teardown
        self.clients = [:]
        self.daemon = nil
        let done = DispatchSemaphore(value: 0)
        // Nothing in here needs the main actor, which stays blocked below.
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for client in clients { group.addTask { await client.stop() } }
                if let daemon { group.addTask { await daemon.stop() } }
                if let teardown { group.addTask { await teardown.value } }   // a sign-out's stops still running
            }
            bridge.stop()
            done.signal()
        }
        if done.wait(timeout: .now() + Self.terminationBudget) == .timedOut {
            RemoteLog.service.error("remote stop exceeded the termination budget")
        }
        bridge.stop()   // idempotent; covers a stop that is still waiting on a hung run
    }

    // MARK: - Account

    /// The user id of the account this Mac last signed in as (`links-owner`), or nil. Share links are kept
    /// per account under it.
    public var accountOwnerID: String? { try? env.store.loadOwner() }

    /// `auth.login` (the password goes straight into the core's JSON), then starts the session. Signing in as
    /// another account than the one `links.json` was saved under drops its link records and invite files.
    public func signIn(email: String, password: String) async throws {
        guard env.gateEnabled(), !terminated else {
            throw ShellXCoreError(code: "disabled", message: "remote machines are turned off")
        }
        await prepareLocal()
        guard !terminated else { return }
        try await ensureConfigured()
        let login = try await call("auth.login", ["email": .string(email), "password": .string(password)], as: LoginReply.self)
        guard !terminated else { return }
        if isSignedIn { await beginTeardown().value }   // another account: start over cleanly
        await teardown?.value                           // a 401's stops: an old link may still save its record
        await adoptAccount(login.user_id)
        guard !terminated else { return }
        RemoteLog.service.info("signed in")
        startSession(list: nil)
    }

    /// Stops host, links and timers, then `auth.logout` (best effort; the core forgets the session anyway).
    public func signOut() async {
        await beginTeardown().value
        guard configuration != nil else { return }
        do { _ = try await call("auth.logout", as: EmptyReply.self) } catch {
            RemoteLog.service.error("logout failed: \(RemoteLog.code(error), privacy: .public)")
        }
    }

    /// `links.json` belongs to one account, whose `user_id` is kept in `links-owner` beside it (only `auth.login`
    /// tells the user id, so a session restored at launch keeps the owner of its last sign-in). Signing in
    /// as a different account, or with no owner on record (links saved before owners were kept), drops every
    /// record and this Mac's invite files, so no link of another account is reconnected. Runs on the links
    /// queue after the last session's links stopped. A failure is logged; the new account's links stay usable.
    func adoptAccount(_ userID: String) async {
        let store = env.store
        let tickets = env.paths.coreStateDir.appendingPathComponent("tickets", isDirectory: true)
        do {
            try await Self.onLinkStore {
                if (try? store.loadOwner()) != userID {
                    let dropped = try store.removeAll()
                    let invites = RemoteInviteSweep.sweep(ticketsDir: tickets, now: Date())
                    if dropped + invites > 0 {
                        RemoteLog.service.notice("new account: dropped \(dropped) link record(s), \(invites) invite file(s)")
                    }
                }
                try store.saveOwner(userID)
            }
        } catch {
            RemoteLog.service.error("link owner not updated: \(RemoteLog.code(error), privacy: .public)")
        }
    }

    // MARK: - Session

    func bootstrap() async {
        await prepareLocal()
        guard !terminated else { return }
        do { try await ensureConfigured() } catch {
            let code = RemoteLog.code(error)
            RemoteLog.service.error("config.set failed: \(code, privacy: .public)")
            hostState = .failed(code: code)
            return
        }
        guard !terminated, !isSignedIn else { return }
        do {
            let list = try await call("machines.list", as: MachineListReply.self)
            guard !terminated, !isSignedIn else { return }
            startSession(list: list)
        } catch {
            guard !terminated, !isSignedIn else { return }
            let code = RemoteLog.code(error)
            if Self.isSignedOutCode(code) {
                RemoteLog.service.info("not signed in")
                if let dev = env.devCredentials {
                    do { try await signIn(email: dev.email, password: dev.password) } catch {
                        RemoteLog.service.error("dev sign-in failed: \(RemoteLog.code(error), privacy: .public)")
                    }
                }
                return
            }
            // The core answers not_logged_in without a local session, so any other error means a session
            // exists and the API is unreachable: keep going, the timers retry.
            RemoteLog.service.error("machines.list failed at launch: \(code, privacy: .public)")
            startSession(list: nil, listImmediately: false)
        }
    }

    /// Before any session: invite files of an earlier run are stale (swept), and whether cmux-tui exists.
    /// Runs once; a sign-in that finishes before the launch sweep waits for the same result.
    func prepareLocal() async {
        let task: Task<Bool, Never>
        if let preparation {
            task = preparation
        } else {
            let paths = env.paths, cmuxTui = env.cmuxTui
            task = Task.detached {
                (try? await Self.offMain { () -> Bool in
                    let tickets = paths.coreStateDir.appendingPathComponent("tickets", isDirectory: true)
                    let removed = RemoteInviteSweep.sweep(ticketsDir: tickets, now: Date())
                    if removed > 0 { RemoteLog.service.info("removed \(removed) stale invite file(s)") }
                    return FileManager.default.isExecutableFile(atPath: cmuxTui.path)
                }) ?? false
            }
            preparation = task
        }
        cmuxTuiAvailable = await task.value
    }

    func ensureConfigured() async throws {
        if let configuration { return try await configuration.value }
        let params: [String: JSONValue] = [
            "api_base": .string(env.apiBase.absoluteString), "state_dir": .string(env.paths.coreStateDir.path),
            "app_version": .string(env.device.appVersion), "os_version": .string(env.device.osVersion),
            "platform": .string("macos"), "device_name": .string(env.device.machineName),
        ]
        let task = Task { _ = try await self.call("config.set", params, as: EmptyReply.self) }
        configuration = task
        do { try await task.value } catch {
            configuration = nil
            throw error
        }
    }

    func startSession(list: MachineListReply?, listImmediately: Bool = true) {
        guard !terminated else { return }
        generation += 1
        let gen = generation
        isSignedIn = true
        if let list { apply(list) }
        setTask("list", repeating(every: Self.machinesInterval, immediate: list == nil && listImmediately, generation: gen) {
            await $0.listTick($1)
        })
        setTask("host", Task { [weak self] in await self?.runSession(gen) })
    }

    func runSession(_ gen: Int) async {
        // Links this Mac already holds; enrolled ones reconnect by themselves while their machine is online.
        // A grant that never enrolled cannot succeed now: its invite file was swept at launch, or dropped when
        // the previous session stopped its link (R33). Such records are removed, but only once the last
        // session's links stopped: one of them may still connect and save `enrolled = true` while stopping.
        await teardown?.value
        guard isCurrent(gen) else { return }
        let store = env.store
        let loaded: [RemoteLinkRecord]
        do {
            loaded = try await Self.onLinkStore {
                let all = try store.load()
                for stale in all where !stale.enrolled { try store.remove(machineID: stale.machineID) }
                return all.filter(\.enrolled)
            }
        } catch {
            RemoteLog.service.error("link records not loaded: \(RemoteLog.code(error), privacy: .public)")
            loaded = []
        }
        guard isCurrent(gen) else { return }
        for record in loaded { records[record.machineID] = record }
        if cmuxTuiAvailable {
            for record in loaded where record.enrolled && clients[record.machineID] == nil { makeClient(record) }
        }
        rebuildMachines()
        await applyAvailability(gen)
        await startHost(gen)
    }

    func startHost(_ gen: Int) async {
        guard cmuxTuiAvailable else {
            RemoteLog.service.error("host not started: cmux-tui is missing")
            hostState = .failed(code: "cmux_tui_missing")
            return
        }
        await teardown?.value
        guard isCurrent(gen) else { return }
        hostState = .connecting
        guard let (route, slot) = await registerHost(gen) else { return }
        hostRoute = route
        let bridge = env.bridge, socket = env.paths.bridgeSocket
        do {
            try await Self.offMain {
                bridge.stop()
                try bridge.start(socket: socket)
            }
        } catch {
            RemoteLog.service.error("bridge did not start: \(String(describing: error), privacy: .public)")
            hostState = .failed(code: "bridge_failed")
            return
        }
        guard isCurrent(gen) else {
            if !isSignedIn { bridge.stop() }
            return
        }
        let daemon = ShellXDaemonSupervisor(paths: env.paths, cmuxTui: env.cmuxTui, core: env.core, refresher: refresher,
                                            launcher: env.launcher, clock: env.clock)
        self.daemon = daemon
        setTask("daemon", Task { [weak self] in
            for await state in daemon.stateStream { self?.hostChanged(state, gen) }
        })
        await daemon.start(route: route, slot: slot)
    }

    /// `machines.register` and the first register-ticket mint (its `relay_url` is the only source of the
    /// relay route), retried on the backoff while the API is unreachable. Nil when the host cannot start.
    func registerHost(_ gen: Int) async -> (route: String, slot: String)? {
        var failures = 0
        while isCurrent(gen) {
            do {
                let registered = try await call("machines.register", [
                    "name": .string(env.device.machineName), "platform": .string("macos"),
                    "os_version": .string(env.device.osVersion), "app_version": .string(env.device.appVersion),
                ], as: RegisterReply.self)
                guard isCurrent(gen) else { return nil }
                thisMachineID = registered.machine_id
                hostSlot = registered.slot
                rebuildMachines()
                startRegisteredTimers(gen)
                let mint = try await call("tickets.mint", ["permission": .string("register"),
                                                           "write_to": .string(ShellXDaemonSupervisor.registerTicketName)],
                                          as: MintReply.self)
                guard isCurrent(gen) else { return nil }
                guard let route = try? RelayRoute.cmuxRoute(from: mint.relay_url) else {
                    throw ShellXCoreError(code: "bad_relay_url", message: "tickets.mint returned an unsupported relay_url")
                }
                return (route, registered.slot)
            } catch {
                guard isCurrent(gen) else { return nil }
                let code = RemoteLog.code(error)
                RemoteLog.service.error("host registration failed: \(code, privacy: .public)")
                if Self.isSignedOutCode(code) { handleSignedOut(gen); return nil }
                if LinkFailure.isFatal(code) || code == "bad_relay_url" { hostState = .failed(code: code); return nil }
                let retryAt = env.clock.now.addingTimeInterval(ReconnectBackoff.delay(attempt: failures))
                failures += 1
                hostState = .reconnecting(attempt: failures, retryAt: retryAt)
                do { try await env.clock.sleep(until: retryAt) } catch { return nil }
            }
        }
        return nil
    }

    func hostChanged(_ state: LinkState, _ gen: Int) {
        guard isCurrent(gen) else { return }
        hostState = state
        if case .failed(let code) = state {
            RemoteLog.service.error("host daemon failed: \(code, privacy: .public)")
            if Self.isSignedOutCode(code) { handleSignedOut(gen) }
        }
    }

    func startRegisteredTimers(_ gen: Int) {
        guard tasks["pending"] == nil else { return }
        setTask("pending", repeating(every: Self.pendingInterval, immediate: true, generation: gen) { await $0.pendingTick($1) })
        setTask("heartbeat", repeating(every: Self.heartbeatInterval, immediate: false, generation: gen) {
            await $0.heartbeatTick($1)
        })
    }

    /// Ends the session now (published state cleared, timers cancelled) and returns the task that stops the
    /// links, the daemon and the bridge.
    @discardableResult
    func beginTeardown() -> Task<Void, Never> {
        generation += 1
        cancelAllTasks()
        resumeAllWaiters(connected: false)
        let clients = Array(self.clients.values), daemon = self.daemon, bridge = env.bridge, previous = teardown
        self.clients = [:]
        self.daemon = nil
        linkStates = [:]; records = [:]; listed = []
        thisMachineID = nil; hostRoute = nil; hostSlot = nil
        gate = ApprovalGate(); handledPairings = []; pairingMemory = [:]
        isSignedIn = false
        machines = []; pendingApprovals = []; outgoing = []; remoteWorkspaces = [:]
        hostState = .idle
        // Detached: `stopForTermination` may block the main actor right after a sign-out and joins this task.
        let task = Task.detached {
            await previous?.value
            for client in clients { await client.stop() }
            await daemon?.stop()
            _ = try? await Self.offMain { bridge.stop() }
        }
        teardown = task
        return task
    }

    func handleSignedOut(_ gen: Int) {
        guard isCurrent(gen), isSignedIn else { return }
        RemoteLog.service.notice("session ended by the server")
        beginTeardown()
    }

    // MARK: - Timers

    func isCurrent(_ gen: Int) -> Bool { gen == generation && !terminated }

    func checkCurrent(_ gen: Int) throws {
        guard isCurrent(gen) else { throw ShellXCoreError(code: "cancelled", message: "the remote session ended") }
    }

    func setTask(_ key: String, _ task: Task<Void, Never>) {
        tasks[key]?.cancel()
        tasks[key] = task
    }

    func cancelAllTasks() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
    }

    /// One task per timer: the next sleep starts only after the tick finished, so calls never overlap.
    /// Fixed rate (`start + n × interval`); beats missed while a tick ran long are skipped, not caught up.
    func repeating(every interval: TimeInterval, immediate: Bool, generation gen: Int,
                   _ tick: @escaping @MainActor @Sendable (ShellXRemoteService, Int) async -> Void) -> Task<Void, Never> {
        let clock = env.clock
        return Task { [weak self] in
            var deadline = immediate ? clock.now : clock.now.addingTimeInterval(interval)
            while !Task.isCancelled {
                do { try await clock.sleep(until: deadline) } catch { return }
                guard let self, self.isCurrent(gen) else { return }
                await tick(self, gen)
                deadline = Self.nextBeat(after: deadline, every: interval, now: clock.now)
            }
        }
    }

    nonisolated static func nextBeat(after deadline: Date, every interval: TimeInterval, now: Date) -> Date {
        let next = deadline.addingTimeInterval(interval)
        return next < now ? now.addingTimeInterval(interval) : next
    }

    func listTick(_ gen: Int) async {
        do {
            let list = try await call("machines.list", as: MachineListReply.self)
            guard isCurrent(gen) else { return }
            apply(list)
            await applyAvailability(gen)
        } catch {
            guard isCurrent(gen) else { return }
            let code = RemoteLog.code(error)
            if Self.isSignedOutCode(code) { handleSignedOut(gen); return }
            RemoteLog.service.info("machines.list failed, keeping the last list: \(code, privacy: .public)")
        }
    }

    func heartbeatTick(_ gen: Int) async {
        do { _ = try await call("machines.heartbeat", as: EmptyReply.self) } catch {
            guard isCurrent(gen) else { return }
            let code = RemoteLog.code(error)
            if Self.isSignedOutCode(code) { handleSignedOut(gen); return }
            RemoteLog.service.info("heartbeat failed: \(code, privacy: .public)")
        }
    }

    // MARK: - Machines

    func apply(_ list: MachineListReply) {
        listed = list.machines
        if thisMachineID == nil, let me = list.machines.first(where: \.isThisMachine) { thisMachineID = me.machine_id }
        rebuildMachines()
    }

    func rebuildMachines() {
        let next = listed.filter { !$0.isThisMachine && $0.machine_id != thisMachineID }.map { item in
            RemoteMachine(id: item.machine_id, name: item.name, platform: RemoteMachine.Platform(rawValue: item.platform) ?? .macos,
                          online: item.online, lastSeen: item.lastSeen, fingerprint: item.fingerprint ?? "",
                          isThisMachine: false, access: access(for: item.machine_id), link: linkStates[item.machine_id] ?? .idle)
        }
        if next != machines { machines = next }
    }

    func access(for machine: RemoteMachine.ID) -> RemoteMachine.Access {
        if records[machine] != nil { return .granted }
        if let waiting = outgoing.last(where: { $0.toMachineID == machine && $0.status == .waiting }) {
            return .requested(pairingID: waiting.id, code: waiting.code)
        }
        return .none
    }

    func machineName(_ id: RemoteMachine.ID) -> String {
        listed.first { $0.machine_id == id }?.name ?? id
    }
}
