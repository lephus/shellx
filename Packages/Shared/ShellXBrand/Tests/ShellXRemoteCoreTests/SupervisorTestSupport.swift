import Foundation
@testable import ShellXRemoteCore

let supT0 = Date(timeIntervalSince1970: 1000)
let supRoute = "relay+wss://relay.test/v2/relay"

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    @discardableResult func with<R>(_ body: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}

/// Ordered record of what the fakes saw, to check mint-before-launch ordering.
final class EventLog: Sendable {
    private let entries = Locked<[String]>([])
    func add(_ entry: String) { entries.with { $0.append(entry) } }
    var all: [String] { entries.get() }
}

/// `sleep(until:)` suspends until the test advances time past the deadline.
final class ManualClock: RemoteClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var nextID = 0
    private var sleepers: [Int: (deadline: Date, cont: CheckedContinuation<Void, any Error>)] = [:]

    init(_ start: Date = supT0) { current = start }

    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    var deadlines: [Date] { lock.lock(); defer { lock.unlock() }; return sleepers.values.map(\.deadline).sorted() }

    func sleep(until deadline: Date) async throws {
        let id: Int = { lock.lock(); defer { lock.unlock() }; nextID += 1; return nextID }()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                lock.lock()
                if Task.isCancelled { lock.unlock(); cont.resume(throwing: CancellationError()); return }
                if deadline <= current { lock.unlock(); cont.resume(); return }
                sleepers[id] = (deadline, cont)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let sleeper = sleepers.removeValue(forKey: id)
            lock.unlock()
            sleeper?.cont.resume(throwing: CancellationError())
        }
    }

    func advance(by seconds: TimeInterval) { advance(to: now.addingTimeInterval(seconds)) }

    func advance(to time: Date) {
        lock.lock()
        current = time
        let due = sleepers.filter { $0.value.deadline <= time }
        for key in due.keys { sleepers.removeValue(forKey: key) }
        lock.unlock()
        for sleeper in due.values { sleeper.cont.resume() }
    }
}

/// Records `(args, env)` of every run/launch; the test drives lines and exits of launched processes.
final class FakeLauncher: SidecarLaunching, @unchecked Sendable {
    struct Call: Sendable {
        enum Kind: Sendable { case run, launch }
        let kind: Kind
        let executable: URL
        let args: [String]
        let env: [String: String]
    }

    final class Proc: SidecarHandle, @unchecked Sendable {
        let onLine: @Sendable (String) -> Void
        let onExit: @Sendable (Int32) -> Void
        private let flag = Locked(false)
        init(onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) {
            self.onLine = onLine; self.onExit = onExit
        }
        var terminated: Bool { flag.get() }
        func terminate() { flag.with { $0 = true } }
    }

    let log: EventLog
    private let recorded = Locked<[Call]>([])
    private let processes = Locked<[Proc]>([])
    /// Reply for `run`; the default says "daemon not up yet" (`enroll status` exits 1).
    let runReply = Locked<@Sendable ([String]) -> (Int32, Data)>({ _ in (1, Data()) })
    let launchFails = Locked(false)

    init(log: EventLog) { self.log = log }

    var calls: [Call] { recorded.get() }
    var runs: [Call] { calls.filter { $0.kind == .run } }
    var launches: [Call] { calls.filter { $0.kind == .launch } }
    var procs: [Proc] { processes.get() }

    /// When set, the next `server stop` run suspends until `releaseHeldRun()`.
    let holdNextServerStop = Locked(false)
    private let held = Locked<CheckedContinuation<Void, Never>?>(nil)
    var isHoldingRun: Bool { held.get() != nil }
    func releaseHeldRun() { held.with { c in let r = c; c = nil; return r }?.resume() }

    func run(_ executable: URL, _ args: [String], env: [String: String]) async throws -> (status: Int32, stdout: Data) {
        recorded.with { $0.append(Call(kind: .run, executable: executable, args: args, env: env)) }
        log.add("run:" + args.prefix(2).joined(separator: " "))
        if args.starts(with: ["server", "stop"]), holdNextServerStop.with({ h in let was = h; h = false; return was }) {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in held.with { $0 = c } }
        }
        let reply = runReply.get()(args)
        return (reply.0, reply.1)
    }

    func launch(_ executable: URL, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) throws -> any SidecarHandle {
        recorded.with { $0.append(Call(kind: .launch, executable: executable, args: args, env: env)) }
        log.add("launch:" + args.prefix(2).joined(separator: " "))
        if launchFails.get() { throw CocoaError(.fileNoSuchFile) }
        let proc = Proc(onLine: onLine, onExit: onExit)
        processes.with { $0.append(proc) }
        return proc
    }

    func line(_ index: Int, _ text: String) { procs[index].onLine(text) }
    func exit(_ index: Int, status: Int32 = 1) { procs[index].onExit(status) }
}

/// Answers `tickets.mint` like shellx-core with `write_to`: `{path, expires_at_unix, relay_url}`.
final class ScriptedCore: ShellXCoreCalling, @unchecked Sendable {
    let clock: ManualClock
    let log: EventLog
    let coreStateDir: URL
    let mints = Locked<[[String: JSONValue]]>([])
    /// Error codes returned by the next calls, first in first out.
    let failures = Locked<[String]>([])
    let lifetime = Locked<TimeInterval>(600)
    let relayURL = Locked("wss://relay.test/v2/relay")

    init(clock: ManualClock, log: EventLog, coreStateDir: URL) {
        self.clock = clock; self.log = log; self.coreStateDir = coreStateDir
    }

    var mintCount: Int { mints.get().count }

    func call(method: String, json: Data) throws -> Data {
        let params = (try? JSONDecoder().decode([String: JSONValue].self, from: json)) ?? [:]
        mints.with { $0.append(params) }
        var permission = "?"
        if case .string(let p)? = params["permission"] { permission = p }
        log.add("mint:" + permission)
        if method != "tickets.mint" {
            return Data(#"{"error":{"code":"unknown_method","message":"m"}}"#.utf8)
        }
        if let code = failures.with({ $0.isEmpty ? nil : $0.removeFirst() }) {
            return Data(#"{"error":{"code":"\#(code)","message":"scripted"}}"#.utf8)
        }
        guard case .string(let name)? = params["write_to"] else {
            return Data(#"{"error":{"code":"invalid_params","message":"m"}}"#.utf8)
        }
        let path = coreStateDir.appendingPathComponent("tickets/" + name).path
        let expires = clock.now.timeIntervalSince1970 + lifetime.get()
        let body: [String: JSONValue] = ["ok": .object(["path": .string(path), "expires_at_unix": .number(expires),
                                                        "relay_url": .string(relayURL.get())])]
        return try JSONEncoder().encode(body)
    }
}

/// A temp home and the fakes wired together.
final class SupervisorRig: @unchecked Sendable {
    let dir: URL
    let paths: RemotePaths
    let clock = ManualClock()
    let log = EventLog()
    let launcher: FakeLauncher
    let core: ScriptedCore
    let refresher: ShellXTicketRefresher
    let cmuxTui = URL(fileURLWithPath: "/Applications/ShellX.app/Contents/Resources/bin/cmux-tui")

    private let ownsDir: Bool

    /// `sharingHomeWith` puts a second bundle under the same home and temp dir (Review Focus 1).
    init(bundleID: String = "pro.shellx.desktop.debug.test", sharingHomeWith other: SupervisorRig? = nil) {
        ownsDir = other == nil
        dir = other?.dir ?? FileManager.default.temporaryDirectory.appendingPathComponent("sx-sup-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        paths = RemotePaths(bundleID: bundleID, home: dir, temporaryDirectory: dir.appendingPathComponent("t", isDirectory: true))
        launcher = FakeLauncher(log: log)
        core = ScriptedCore(clock: clock, log: log, coreStateDir: paths.coreStateDir)
        refresher = ShellXTicketRefresher(core: ShellXCoreClient(core), clock: clock)
    }

    deinit { if ownsDir { try? FileManager.default.removeItem(at: dir) } }

    var registerTicket: URL { paths.coreStateDir.appendingPathComponent("tickets/register.ticket") }

    func daemon() -> ShellXDaemonSupervisor {
        ShellXDaemonSupervisor(paths: paths, cmuxTui: cmuxTui, core: ShellXCoreClient(core), refresher: refresher,
                               launcher: launcher, clock: clock)
    }

    var store: RemoteLinkStore { RemoteLinkStore(file: paths.stateRoot.appendingPathComponent("links.json")) }

    func record(enrolled: Bool = false) -> RemoteLinkRecord {
        RemoteLinkRecord(machineID: "m_1", route: supRoute, slot: "S9", daemonFingerprint: "a1b2c3d4e5f60718", enrolled: enrolled)
    }

    func client(record: RemoteLinkRecord? = nil) -> ShellXClientLinkSupervisor {
        ShellXClientLinkSupervisor(machine: "m_1", record: record ?? self.record(), deviceName: "Phu's Mac", paths: paths,
                                   cmuxTui: cmuxTui, refresher: refresher, launcher: launcher, clock: clock, store: store)
    }

    /// An invite file like `pair.poll {write_invite_to}` leaves in the core state dir.
    func makeInvite() throws -> URL {
        let invites = dir.appendingPathComponent("invites", isDirectory: true)
        try FileManager.default.createDirectory(at: invites, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = invites.appendingPathComponent("invite-m_1")
        try Data("cmux://enroll/not-a-real-invite".utf8).write(to: url)
        return url
    }
}

/// Polls a condition, yielding (and every few rounds sleeping 1 ms so background queues can finish).
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for round in 0..<6000 {
        if await condition() { return true }
        if round % 3 == 2 { try? await Task.sleep(nanoseconds: 1_000_000) } else { await Task.yield() }
    }
    return await condition()
}

/// Lets queued tasks run before a "nothing more happened" check.
func settle() async {
    for _ in 0..<50 { await Task.yield() }
    try? await Task.sleep(nanoseconds: 5_000_000)
    for _ in 0..<50 { await Task.yield() }
}

extension LinkState {
    var retryAt: Date? { if case .reconnecting(_, let at) = self { return at }; return nil }
}
