import Foundation
@testable import ShellXRemoteCore

/// Answers every K3 method the service uses, the way shellx-core shapes its replies
/// (`shellx-core/src/{machines,tickets,pairing,auth}.rs`), and records each call with the thread it ran on.
final class FakeRemoteCore: ShellXCoreCalling, @unchecked Sendable {
    struct Call: Sendable {
        let method: String
        let params: [String: JSONValue]
        let onMainThread: Bool
    }

    static let ownFingerprint = "f00dfeedf00dfeed"
    static let relayURL = "wss://relay.test/v2/relay"

    let clock: ManualClock
    let log: EventLog
    let coreStateDir: URL
    private let recorded = Locked<[Call]>([])
    let signedIn = Locked(true)
    /// The email `auth.google.finish` signs in.
    let googleEmail = Locked("g@shellx.test")
    /// `account.identities.list` items.
    let identities = Locked<[JSONValue]>([])
    /// The code `auth.email.finish` accepts (leading zeros, so they are always exercised).
    let emailCode = Locked("004217")
    /// The address of the last `auth.email.begin`, trimmed and lowercased as the relay answers it.
    let emailAddress = Locked<String?>(nil)
    /// What `auth.session` reports (`auth.login` / `auth.google.finish` / `auth.email.finish` set them).
    let sessionEmail = Locked<String?>(nil)
    let sessionAuthMethod = Locked("password")
    /// The account `auth.login` signs into.
    let userID = Locked("u_1")
    /// `machines.list` items (shellx-core shape, incl. `is_this_machine`).
    let machines = Locked<[JSONValue]>([FakeRemoteCore.machine("m_self", "Phu's Mac (DEV t)", online: true, thisMachine: true),
                                        FakeRemoteCore.machine("m_1", "Mac mini", online: true)])
    /// `pair.pending` items.
    let pending = Locked<[JSONValue]>([])
    /// `machines.register`'s `link_slot`; nil answers like a relay that predates the link lane (no field).
    let linkSlot = Locked<String?>("link-self")
    /// The slot claim of link-lane tickets; nil means "the registered link slot".
    let linkTicketSlot = Locked<String?>(nil)
    /// `pair.poll` status per pairing id (default `pending`).
    let pollStatus = Locked<[String: String]>([:])
    /// Error codes returned by the next calls of a method, first in first out.
    let failures = Locked<[String: [String]]>([:])
    /// Error code returned by every call of a method until removed (API down).
    let down = Locked<[String: String]>([:])
    /// Runs inside the call (on the caller's thread) before the reply is built.
    let onCall = Locked<(@Sendable (String) -> Void)?>(nil)
    /// When set, the next call of this method blocks (on its global-queue thread) until `releaseHeldCall()`.
    let holdNext = Locked<String?>(nil)
    private let heldGate = DispatchSemaphore(value: 0)
    private let holding = Locked(false)
    var isHoldingCall: Bool { holding.get() }
    func releaseHeldCall() { heldGate.signal() }

    init(clock: ManualClock, log: EventLog, coreStateDir: URL) {
        self.clock = clock; self.log = log; self.coreStateDir = coreStateDir
    }

    var calls: [Call] { recorded.get() }
    var methods: [String] { calls.map(\.method) }
    func count(_ method: String) -> Int { calls.filter { $0.method == method }.count }
    func lastParams(_ method: String) -> [String: JSONValue]? { calls.last { $0.method == method }?.params }

    static func machine(_ id: String, _ name: String, online: Bool, lastSeen: Double = 0, thisMachine: Bool = false) -> JSONValue {
        .object(["is_this_machine": .bool(thisMachine), "machine_id": .string(id), "name": .string(name),
                 "platform": .string("macos"), "online": .bool(online), "last_seen_unix": .number(lastSeen),
                 "fingerprint": .string("fp-" + id)])
    }

    static func pairing(_ id: String, from: String = "m_1", code: String = "123456", fingerprint: String = "a1b2c3d4e5f60718",
                        suspicious: Bool = false) -> JSONValue {
        .object(["pairing_id": .string(id), "from_machine_id": .string(from), "code": .string(code),
                 "fingerprint": .string(fingerprint), "server_fingerprint": .string(suspicious ? "0000000000000000" : fingerprint),
                 "suspicious": .bool(suspicious)])
    }

    func call(method: String, json: Data) throws -> Data {
        let params = (try? JSONDecoder().decode([String: JSONValue].self, from: json)) ?? [:]
        onCall.get()?(method)                       // before the call becomes visible to the test
        if holdNext.with({ held in let hit = held == method; if hit { held = nil }; return hit }) {
            holding.with { $0 = true }
            heldGate.wait()
            holding.with { $0 = false }
        }
        recorded.with { $0.append(Call(method: method, params: params, onMainThread: Thread.isMainThread)) }
        log.add("core:" + method)
        if let code = failures.with({ $0[method]?.isEmpty == false ? $0[method]!.removeFirst() : nil }) ?? down.get()[method] {
            return Self.error(code)
        }
        let needsSession = method.hasPrefix("machines.") || method.hasPrefix("tickets.") || method.hasPrefix("pair.") || method.hasPrefix("account.")
        if needsSession && !signedIn.get() { return Self.error("not_logged_in") }
        switch method {
        case "config.set", "machines.heartbeat", "pair.approve", "pair.deny":
            return Self.ok(.object([:]))
        case "auth.login":
            guard params["password"] == .string("pw") else { return Self.error("invalid_credentials") }
            signedIn.with { $0 = true }
            if case .string(let email)? = params["email"] { sessionEmail.with { $0 = email } }
            sessionAuthMethod.with { $0 = "password" }
            return Self.ok(.object(["user_id": .string(userID.get()), "device_id": .string("d_1"),
                                    "device_public_key_b64": .string("AAAA"), "fingerprint": .string(Self.ownFingerprint)]))
        case "auth.google.begin":
            guard case .string(let purpose)? = params["purpose"], purpose == "sign_in" || purpose == "link" else {
                return Self.error("invalid_params")
            }
            if purpose == "link" && !signedIn.get() { return Self.error("not_logged_in") }
            return Self.ok(.object(["flow_id": .string("flow-1"),
                                    "auth_url": .string("https://accounts.google.com/o/oauth2/v2/auth?client_id=test")]))
        case "auth.google.finish":
            signedIn.with { $0 = true }
            sessionEmail.with { $0 = googleEmail.get() }
            sessionAuthMethod.with { $0 = "google" }
            return Self.ok(.object(["user_id": .string(userID.get()), "device_id": .string("d_1"),
                                    "device_public_key_b64": .string("AAAA"), "fingerprint": .string(Self.ownFingerprint),
                                    "email": .string(googleEmail.get()), "auth_method": .string("google")]))
        case "auth.google.cancel":
            return Self.ok(.object([:]))
        case "auth.email.begin":
            guard case .string(let email)? = params["email"] else { return Self.error("invalid_params") }
            let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            emailAddress.with { $0 = address }
            return Self.ok(.object(["challenge_id": .string("ch-1"), "expires_in": .number(600), "resend_in": .number(60),
                                    "email": .string(address)]))
        case "auth.email.finish":
            guard params["challenge_id"] == .string("ch-1") else { return Self.error("code_expired") }
            guard params["code"] == .string(emailCode.get()) else { return Self.error("invalid_code") }
            let address = emailAddress.get() ?? ""
            signedIn.with { $0 = true }
            sessionEmail.with { $0 = address }
            sessionAuthMethod.with { $0 = "email" }
            return Self.ok(.object(["user_id": .string(userID.get()), "device_id": .string("d_1"),
                                    "device_public_key_b64": .string("AAAA"), "fingerprint": .string(Self.ownFingerprint),
                                    "email": .string(address), "auth_method": .string("email")]))
        case "auth.session":
            guard signedIn.get() else { return Self.error("not_logged_in") }
            return Self.ok(.object(["user_id": .string(userID.get()), "device_id": .string("d_1"),
                                    "email": sessionEmail.get().map { .string($0) } ?? .null,
                                    "auth_method": .string(sessionAuthMethod.get())]))
        case "account.identities.list":
            return Self.ok(.object(["identities": .array(identities.get())]))
        case "account.identities.remove":
            guard case .string(let id)? = params["identity_id"] else { return Self.error("invalid_params") }
            identities.with { items in
                items.removeAll { if case .object(let o) = $0, o["identity_id"] == .string(id) { return true } else { return false } }
            }
            return Self.ok(.object([:]))
        case "auth.logout":
            signedIn.with { $0 = false }
            return Self.ok(.object([:]))
        case "machines.register":
            var reply: [String: JSONValue] = ["machine_id": .string("m_self"), "slot": .string("slot-self")]
            if let link = linkSlot.get() { reply["link_slot"] = .string(link) }
            return Self.ok(.object(reply))
        case "machines.list":
            return Self.ok(.object(["machines": .array(machines.get())]))
        case "tickets.mint" where params["lane"] == .string("link"):
            guard let slot = linkTicketSlot.get() ?? linkSlot.get() else { return Self.error("not_registered") }
            return Self.ok(.object(["ticket": .string(Self.ticket(slot: slot)),
                                    "expires_at_unix": .number(clock.now.timeIntervalSince1970 + 120),
                                    "relay_url": .string(Self.relayURL)]))
        case "tickets.mint":
            guard case .string(let name)? = params["write_to"] else { return Self.error("invalid_params") }
            return Self.ok(.object(["path": .string(coreStateDir.appendingPathComponent("tickets/" + name).path),
                                    "expires_at_unix": .number(clock.now.timeIntervalSince1970 + 600),
                                    "relay_url": .string(Self.relayURL)]))
        case "pair.request":
            return Self.ok(.object(["pairing_id": .string("p_out"), "code": .string("123456"),
                                    "fingerprint": .string(Self.ownFingerprint)]))
        case "pair.pending":
            return Self.ok(.object(["pairings": .array(pending.get())]))
        case "pair.poll":
            guard case .string(let id)? = params["pairing_id"] else { return Self.error("invalid_params") }
            let status = pollStatus.get()[id] ?? "pending"
            guard status == "approved", case .string(let name)? = params["write_invite_to"] else {
                return Self.ok(.object(["status": .string(status)]))
            }
            return Self.ok(.object(["status": .string("approved"),
                                    "invite_path": .string(coreStateDir.appendingPathComponent("tickets/" + name).path),
                                    "relay_route": .string("relay+wss://relay.test/v2/relay"), "relay_slot": .string("slot-m1"),
                                    "daemon_fingerprint": .string("dfp-m1")]))
        default:
            return Self.error("unknown_method")
        }
    }

    /// A relay v2 ticket whose claims name `slot` (`v2.<base64url claims>.<signature>`).
    static func ticket(slot: String) -> String {
        let claims = Data(#"{"slot":"\#(slot)","permission":"register"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "v2.\(claims).c2ln"
    }

    private static func ok(_ value: JSONValue) -> Data { (try? JSONEncoder().encode(["ok": value])) ?? Data() }
    private static func error(_ code: String) -> Data {
        Data(#"{"error":{"code":"\#(code)","message":"scripted"}}"#.utf8)
    }
}

/// Records bridge starts and stops (in the shared event log too, for ordering checks).
final class FakeBridge: RemoteBridgeControlling, @unchecked Sendable {
    let log: EventLog
    let starts = Locked<[URL]>([])
    let stops = Locked(0)
    init(log: EventLog) { self.log = log }
    func start(socket: URL) throws { log.add("bridge:start"); starts.with { $0.append(socket) } }
    func stop() { log.add("bridge:stop"); stops.with { $0 += 1 } }
}

/// Records the link host's starts and stops (in the shared event log too, for ordering checks).
@MainActor
final class FakeLinkHost: RemoteLinkHosting {
    struct Start: Equatable { let machineID: String; let linkSlot: String; let accountID: String }
    let log: EventLog
    private(set) var starts: [Start] = []
    private(set) var stops = 0
    init(log: EventLog) { self.log = log }
    func start(machineID: String, linkSlot: String, accountID: String) {
        log.add("link:start")
        starts.append(Start(machineID: machineID, linkSlot: linkSlot, accountID: accountID))
    }
    func stop() { log.add("link:stop"); stops += 1 }
}

@MainActor
final class FakeOpener: RemoteWorkspaceOpening {
    struct Opened { let title: String; let command: String; let id: UUID }
    private(set) var opened: [Opened] = []
    func openRemoteTerminal(title: String, attachCommand: String) -> UUID? {
        let id = UUID()
        opened.append(Opened(title: title, command: attachCommand, id: id))
        return id
    }
}

/// The service built from fakes, a manual clock and a temp home (`SupervisorRig`'s launcher, clock and paths).
@MainActor
final class ServiceRig {
    struct Stub { let key: [String]; var replies: [(Int32, Data)] }

    static let statusUp = #"{"daemon_name":"Phu's Mac","daemon_fingerprint":"fp-daemon","connected_clients":0}"#
    static let device = ShellXRemoteDevice(machineName: "Phu's Mac (DEV t)", appVersion: "2.0.0", osVersion: "26.0.0")

    let base = SupervisorRig()
    let core: FakeRemoteCore
    let bridge: FakeBridge
    let opener = FakeOpener()
    let linkHost: FakeLinkHost
    let gate: Locked<Bool>
    let cmuxTui: URL
    let stubs = Locked<[Stub]>([])
    let service: ShellXRemoteService

    var paths: RemotePaths { base.paths }
    var clock: ManualClock { base.clock }
    var launcher: FakeLauncher { base.launcher }
    var log: EventLog { base.log }
    var store: RemoteLinkStore { base.store }
    var hostConnected: LinkState { .connected(localSocket: paths.muxSocket.path) }

    /// - Parameters:
    ///   - owner: The `links-owner` a restored session (`signedIn`) starts with. Nil is a session signed in
    ///     before owners were kept for it (ShellX 1.4.0 and 1.5.0 signed in from Settings › Account only).
    ///   - remoteMachines: False runs the session for phones only (`remoteMachinesEnabled` off).
    init(gate gateOn: Bool = true, signedIn: Bool = true, owner: String? = "u_1", cmuxTuiPresent: Bool = true,
         devCredentials: ShellXRemoteDevCredentials? = nil, remoteMachines: Bool = true) {
        core = FakeRemoteCore(clock: base.clock, log: base.log, coreStateDir: base.paths.coreStateDir)
        core.signedIn.with { $0 = signedIn }
        // A restored session keeps the owner of its last sign-in; the link host is scoped by it.
        if signedIn, let owner { try? base.store.saveOwner(owner) }
        bridge = FakeBridge(log: base.log)
        linkHost = FakeLinkHost(log: base.log)
        gate = Locked(gateOn)
        cmuxTui = base.dir.appendingPathComponent("bin/cmux-tui")
        if cmuxTuiPresent {
            try? FileManager.default.createDirectory(at: cmuxTui.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: cmuxTui.path, contents: Data("#!/bin/sh\n".utf8),
                                           attributes: [.posixPermissions: 0o755])
        }
        let stubs = self.stubs
        base.launcher.runReply.with { $0 = { args in
            stubs.with { list -> (Int32, Data) in
                guard let index = list.firstIndex(where: { ServiceRig.contains(args, $0.key) }) else { return (0, Data()) }
                let reply = list[index].replies[0]
                if list[index].replies.count > 1 { list[index].replies.removeFirst() }
                return reply
            }
        } }
        let gate = self.gate
        service = ShellXRemoteService(environment: ShellXRemoteEnvironment(
            core: ShellXCoreClient(core), launcher: base.launcher, clock: base.clock, paths: base.paths, cmuxTui: cmuxTui,
            apiBase: URL(string: "http://127.0.0.1:8787")!, device: Self.device, gateEnabled: { gate.get() },
            devCredentials: devCredentials, bridge: bridge, workspaceOpener: opener, linkHost: linkHost,
            remoteMachinesEnabled: { remoteMachines }))
        stub(["remote", "enroll", "status"], stdout: Self.statusUp)
        stub(["remote", "enroll", "pending"], stdout: "[]")
    }

    /// `run` replies for argv containing `key` (latest stub first); the last reply of a sequence repeats.
    func stub(_ key: [String], status: Int32 = 0, stdout: String) { stubSequence(key, [stdout], status: status) }

    func stubSequence(_ key: [String], _ outputs: [String], status: Int32 = 0) {
        stubs.with { $0.insert(Stub(key: key, replies: outputs.map { (status, Data($0.utf8)) }), at: 0) }
    }

    func ran(_ args: [String]) -> Bool { launcher.runs.contains { $0.args == args } }

    nonisolated static func contains(_ args: [String], _ key: [String]) -> Bool {
        guard !key.isEmpty, key.count <= args.count else { return false }
        return (0...(args.count - key.count)).contains { Array(args[$0..<($0 + key.count)]) == key }
    }

    /// Index (in `launcher.launches` and `launcher.procs`) of the first `remote connect` for a machine.
    var connectIndex: Int? { launcher.launches.firstIndex { $0.args.starts(with: ["remote", "connect"]) } }

    func seedRecord(_ machine: String = "m_1", enrolled: Bool = true) throws {
        try store.upsert(RemoteLinkRecord(machineID: machine, route: "relay+wss://relay.test/v2/relay", slot: "slot-m1",
                                          daemonFingerprint: "dfp-m1", enrolled: enrolled))
    }

    /// Starts the service and waits for the host daemon to answer `enroll status`.
    func startConnected() async -> Bool {
        service.startIfEnabled()
        return await until { self.service.hostState == self.hostConnected }
    }

    /// True once timers sleep until each of `supT0 + offsets`: nothing is in flight then.
    func quiet(at offsets: [TimeInterval]) async -> Bool {
        let wanted = Set(offsets.map { supT0.addingTimeInterval($0) })
        return await until { wanted.isSubset(of: Set(self.clock.deadlines)) }
    }

    /// Waits until a timer sleeps until `now + seconds`, moves the clock there and waits for a new `method` call.
    func advance(_ seconds: TimeInterval, waitingFor method: String) async -> Bool {
        await advance(to: clock.now.addingTimeInterval(seconds), waitingFor: method)
    }

    /// Waits until a timer sleeps until `target`, moves the clock there and waits for a new `method` call.
    func advance(to target: Date, waitingFor method: String) async -> Bool {
        guard await until({ self.clock.deadlines.contains(target) }) else { return false }
        let before = core.count(method)
        clock.advance(to: target)
        return await until { self.core.count(method) > before }
    }
}

/// Polls a main-actor condition, letting other tasks run in between.
@MainActor
func until(_ condition: @MainActor () -> Bool) async -> Bool {
    for round in 0..<6000 {
        if condition() { return true }
        if round % 3 == 2 { try? await Task.sleep(nanoseconds: 1_000_000) } else { await Task.yield() }
    }
    return condition()
}

/// The `ShellXCoreError.code` an async call throws, or nil when it does not throw.
@MainActor
func errorCode(_ body: () async throws -> Void) async -> String? {
    do { try await body(); return nil } catch { return (error as? ShellXCoreError)?.code ?? "\(type(of: error))" }
}

private func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// A cmux enrollment invite as `remote enroll create` prints it (`cmux-remote/src/identity.rs`).
func fixtureInviteURI(id: String) -> String {
    let key = Data(repeating: 9, count: 32)
    let json = """
    {"version":1,"id":"\(id)","secret":"S3CRET","daemon_public_key":"\(b64url(key))","daemon_fingerprint":"\(b64url(Data(SHA256Pure.digest(key).prefix(16))))","daemon_name":"B","expires_at_unix":4102444800,"route_hints":["relay+wss://relay.test/v2/relay"],"relay_access":[{"route":"relay+wss://relay.test/v2/relay","slot":"slot-self","ticket":"TICKET"}],"approval_required":true}
    """
    return "cmux://enroll/" + b64url(Data(json.utf8))
}
