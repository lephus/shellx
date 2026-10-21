import AppKit
import Combine
import Foundation
import ShellXRemoteCore
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// L7 Task B6: the workspace share source, the share controller and the share entrypoints, against a
// fake shellx-core and a fake relay socket factory (no network).

/// Records every core call and answers the share methods like the fake API (ruling 6: the client
/// proposes the id; `takenIDs` answer 409 `share_id_taken`).
final class ShareFakeCore: ShellXCoreCalling, @unchecked Sendable {
    struct Call { let method: String; let json: String; let params: [String: Any] }
    private let lock = NSLock()
    private var recorded: [Call] = []
    private var issued = 0
    var takenIDs: Set<String> = []
    /// `shares.host_ticket` answers this error code instead of a ticket.
    var hostTicketError: String?

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }

    /// Deterministic proposals for `newShareID`.
    func nextID() -> String {
        lock.lock(); defer { lock.unlock() }
        issued += 1
        return String(format: "k7f29q%02d", issued)
    }

    func call(method: String, json: Data) throws -> Data {
        let params = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
        lock.lock()
        recorded.append(Call(method: method, json: String(decoding: json, as: UTF8.self), params: params))
        lock.unlock()
        let now = Int(Date().timeIntervalSince1970)
        let reply: String
        switch method {
        case "shares.create":
            guard let id = params["id"] as? String else {
                return Data(#"{"error":{"code":"bad_request","message":"no id"}}"#.utf8)
            }
            if takenIDs.contains(id) {
                return Data(#"{"error":{"code":"share_id_taken","message":"taken"}}"#.utf8)
            }
            let claim = (params["one_time"] as? Bool) == true ? "\(now + 120)" : "null"
            reply = #"{"ok":{"id":"\#(id)","slot":"slot-\#(id)","expires_at_unix":\#(now + 3600),"claim_until_unix":\#(claim)}}"#
        case "shares.host_ticket":
            if let hostTicketError {
                return Data(#"{"error":{"code":"\#(hostTicketError)","message":"gone"}}"#.utf8)
            }
            reply = #"{"ok":{"ticket":"tkt","expires_at_unix":\#(now + 120),"relay_url":"wss://relay.invalid/v2/relay"}}"#
        case "shares.revoke":
            reply = #"{"ok":{}}"#
        default:
            reply = #"{"error":{"code":"unknown_method","message":"no"}}"#
        }
        return Data(reply.utf8)
    }

    func revokedIDs() -> [String] {
        calls.filter { $0.method == "shares.revoke" }.compactMap { $0.params["id"] as? String }
    }
}

/// A relay socket that never answers; `close` ends every pending receive.
final class ShareFakeSocket: ShareSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<ShareSocketMessage, any Error>] = []
    private var closed = false
    private(set) var sentText: [String] = []

    func send(text: String) async throws { lock.withLock { sentText.append(text) } }
    func send(data: Data) async throws {}

    func receive() async throws -> ShareSocketMessage {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if closed { lock.unlock(); cont.resume(throwing: URLError(.networkConnectionLost)); return }
            waiters.append(cont)
            lock.unlock()
        }
    }

    func close() {
        lock.lock()
        closed = true
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending { waiter.resume(throwing: URLError(.networkConnectionLost)) }
    }
}

final class ShareFakeSocketFactory: ShareSocketFactory, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var opened: [URL] = []

    func open(_ url: URL) async throws -> any ShareSocket {
        lock.withLock { opened.append(url) }
        return ShareFakeSocket()
    }
}

@MainActor
final class ShareFakeTerminalIO: ShellXShareTerminalIO {
    var grid = (cols: 100, rows: 30)
    var tail = "$ echo hi\r\nhi\r\n$ "
    private(set) var writes: [(surface: UUID, bytes: Data)] = []

    func grid(_ panel: TerminalPanel) -> (cols: Int, rows: Int)? { grid }
    func screenTailVT(_ panel: TerminalPanel) -> String? { tail }
    func write(_ bytes: Data, to panel: TerminalPanel) { writes.append((panel.id, bytes)) }
}

final class ShareByteCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ data: Data) { lock.lock(); bytes.append(data); lock.unlock() }
    var received: Data { lock.lock(); defer { lock.unlock() }; return bytes }
}

/// A `ShareHost` stand-in that records how it was stopped.
final class ShareFakeHost: ShellXShareHosting, @unchecked Sendable {
    let spec: ShellXShareEnvironment.HostSpec
    let viewerStream: AsyncStream<[ShareViewer]>
    private let continuation: AsyncStream<[ShareViewer]>.Continuation
    private let lock = NSLock()
    private var stops: [String] = []

    init(spec: ShellXShareEnvironment.HostSpec) {
        self.spec = spec
        (viewerStream, continuation) = AsyncStream.makeStream(of: [ShareViewer].self)
    }

    /// "stop:revoked", "terminate:host_quit", …
    var stopCalls: [String] { lock.withLock { stops } }

    /// When set, `stop` waits until the gate opens.
    var stopGate: ShareStopGate?

    func start() async {}
    func stop(reason: ShareByeReason) async {
        lock.withLock { stops.append("stop:\(reason.rawValue)") }
        if let stopGate { await stopGate.wait() }
        continuation.finish()
    }
    func stopForTermination(reason: ShareByeReason) async {
        lock.withLock { stops.append("terminate:\(reason.rawValue)") }
        continuation.finish()
    }
    func publish(_ viewers: [ShareViewer]) { continuation.yield(viewers) }
    /// The host ended on its own (as `ShareHost` does at `expiresAt`).
    func finish() { continuation.finish() }
}

@MainActor
final class ShareFakeHosts {
    private(set) var made: [ShareFakeHost] = []
    func make(_ spec: ShellXShareEnvironment.HostSpec) -> any ShellXShareHosting {
        let host = ShareFakeHost(spec: spec)
        made.append(host)
        return host
    }
    func host(_ apiID: String) -> ShareFakeHost? { made.last { $0.spec.shareID == apiID } }
}

@MainActor
final class ShareMemoryStore: ShellXShareStore {
    var byAccount: [String: [PersistedShare]] = [:]
    /// The default test account's list.
    var shares: [PersistedShare] {
        get { byAccount[ShellXShareTests.accountA] ?? [] }
        set { byAccount[ShellXShareTests.accountA] = newValue }
    }
    func load(account: String) -> [PersistedShare] { byAccount[account] ?? [] }
    func save(_ shares: [PersistedShare], account: String) { byAccount[account] = shares }
}

/// Test-driven sign-in, restore and account state.
@MainActor
final class ShareSession {
    let signedIn: CurrentValueSubject<Bool, Never>
    let restored: CurrentValueSubject<Bool, Never>
    var account: String? = ShellXShareTests.accountA
    /// Workspaces that exist (nil: the fixture's workspace exists).
    var workspaceExists = true

    init(signedIn: Bool = true, restored: Bool = true) {
        self.signedIn = CurrentValueSubject(signedIn)
        self.restored = CurrentValueSubject(restored)
    }
}

final class ShareStopGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var opened = false
    var isWaiting: Bool { lock.withLock { waiter != nil } }

    func wait() async {
        await withCheckedContinuation { cont in
            let resumeNow = lock.withLock { () -> Bool in
                if opened { return true }
                waiter = cont
                return false
            }
            if resumeNow { cont.resume() }
        }
    }

    func open() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            opened = true
            defer { waiter = nil }
            return waiter
        }
        pending?.resume()
    }
}

/// Sleeps until `fireAll`.
final class ShareManualSleeper: ShareSleeper, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, any Error>] = []
    var waiting: Int { lock.withLock { waiters.count } }

    func sleep(until deadline: Date) async throws {
        try await withCheckedThrowingContinuation { cont in lock.withLock { waiters.append(cont) } }
    }

    func fireAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            defer { waiters = [] }
            return waiters
        }
        for waiter in pending { waiter.resume() }
    }
}

@MainActor
@Suite(.serialized)
struct ShellXShareTests {
    nonisolated static let accountA = "user-a"
    struct Fixture {
        let manager: TabManager
        let workspace: Workspace
        let terminalID: UUID
        let browser: BrowserPanel
        let io: ShareFakeTerminalIO
        let source: WorkspaceShareSource
    }

    private func makeFixture() throws -> Fixture {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let terminalID = try #require(workspace.focusedPanelId)
        let browser = try #require(workspace.newBrowserSplit(
            from: terminalID, orientation: .horizontal, url: URL(string: "about:blank"),
            focus: false, initialDividerPosition: 0.5, websiteDataStore: .nonPersistent()
        ))
        let io = ShareFakeTerminalIO()
        return Fixture(manager: manager, workspace: workspace, terminalID: terminalID, browser: browser, io: io,
                       source: WorkspaceShareSource(workspace: workspace, io: io))
    }

    private func makeController(core: ShareFakeCore, sockets: ShareFakeSocketFactory = ShareFakeSocketFactory(),
                                workspace: Workspace?, signedIn: Bool = true,
                                store: ShareMemoryStore? = nil,
                                sleeper: (any ShareSleeper)? = nil,
                                hosts: ShareFakeHosts? = nil,
                                session: ShareSession? = nil) -> ShellXShareController {
        let session = session ?? ShareSession(signedIn: signedIn)
        var env = ShellXShareEnvironment(
            core: ShellXCoreClient(core), sockets: sockets,
            signedIn: session.signedIn.eraseToAnyPublisher(),
            sessionRestored: session.restored.eraseToAnyPublisher(),
            accountID: { session.account },
            presentSignIn: {},
            source: { [weak workspace] id in
                guard session.workspaceExists, let workspace, workspace.id == id else { return nil }
                return WorkspaceShareSource(workspace: workspace, io: ShareFakeTerminalIO())
            },
            store: store ?? ShareMemoryStore(),
            newShareID: { core.nextID() })
        if let sleeper { env.sleeper = sleeper }
        if let hosts { env.makeHost = { hosts.make($0) } }
        return ShellXShareController(environment: env)
    }

    /// Polls `condition` on the main actor for up to 2 s.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func testSourceListsTerminalAndPlaceholderPanes() throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let panes = f.source.panes
        #expect(panes.map(\.id) == f.workspace.orderedPanelIds.map(\.uuidString))
        #expect(panes.count == 2)
        let terminal = try #require(panes.first { $0.id == f.terminalID.uuidString })
        #expect(terminal.kind == .terminal)
        #expect(terminal.cols == 100 && terminal.rows == 30)
        let browser = try #require(panes.first { $0.id == f.browser.id.uuidString })
        #expect(browser.kind == .browser)
        #expect(f.source.snapshot(pane: browser.id) == nil, "a placeholder pane has nothing to replay")
        #expect(f.source.activePane == f.terminalID.uuidString)
        #expect(WorkspaceShareSource.kind(of: .agentSession) == .agent)
    }

    @Test func testSourceInputReachesSurface() throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let typed = Data("chào\r".utf8)
        f.source.input(pane: f.terminalID.uuidString, typed)
        f.source.input(pane: f.browser.id.uuidString, Data("x".utf8))
        f.source.input(pane: "not-a-pane", Data("y".utf8))
        #expect(f.io.writes.count == 1)
        #expect(f.io.writes.first?.surface == f.terminalID)
        #expect(f.io.writes.first?.bytes == typed, "byte-exact, once")

        let snapshot = try #require(f.source.snapshot(pane: f.terminalID.uuidString))
        #expect(snapshot.cols == 100 && snapshot.rows == 30)
        #expect(snapshot.vt == Data(("\u{1b}[H\u{1b}[2J" + f.io.tail).utf8))
    }

    @Test func testTeeSinkReceivesOutputOnlyWhileSubscribed() throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let collector = ShareByteCollector()
        let first = Array("\u{1}shellx-share-tee-first".utf8), second = Array("\u{1}shellx-share-tee-second".utf8)
        var token: AnyObject? = f.source.subscribe(pane: f.terminalID.uuidString) { collector.append($0) }
        #expect(ShellXBridgeTee.isBound(surfaceID: f.terminalID))
        first.withUnsafeBufferPointer { ShellXBridgeTee.consume(surfaceID: f.terminalID, buffer: $0) }
        #expect(token != nil)
        token = nil
        second.withUnsafeBufferPointer { ShellXBridgeTee.consume(surfaceID: f.terminalID, buffer: $0) }
        #expect(!ShellXBridgeTee.isBound(surfaceID: f.terminalID))
        let received = collector.received
        #expect(received.range(of: Data(first)) != nil)
        #expect(received.range(of: Data(second)) == nil)
    }

    @Test func testShareDefaultsAreViewAndOneHour() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore()
        let controller = makeController(core: core, workspace: f.workspace)
        let model = ShellXSharePopoverModel(workspaceID: f.workspace.id, controller: controller)
        #expect(model.permission == .view)
        #expect(model.lifetime == .oneHour)
        await model.create()
        #expect(model.errorText == nil)
        let create = try #require(core.calls.first { $0.method == "shares.create" })
        #expect(create.params["permission"] as? String == "view")
        #expect(create.params["lifetime"] as? String == "1h")
        #expect(create.params["one_time"] as? Bool == false)
        let share = try #require(model.share)
        #expect(share.permission == .view && share.lifetime == .oneHour && !share.oneTime)
        await controller.stopAll()
    }

    @Test func testShareURLHasIdPathAndSecretFragment() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore()
        let controller = makeController(core: core, workspace: f.workspace)
        let url = try await controller.share(workspaceID: f.workspace.id)
        let text = url.absoluteString
        let pattern = #"^https://shellx\.pro/s/[0-9a-hjkmnp-tv-z]{4}-[0-9a-hjkmnp-tv-z]{4}#[A-Za-z0-9_-]{43}$"#
        #expect(text.range(of: pattern, options: .regularExpression) != nil, "\(text)")
        let secret = try #require(url.fragment)
        #expect(ShareSecret(base64url: secret) != nil)
        #expect(controller.active.first?.id == "k7f2-9q01")
        // Let the host mint its relay ticket, then check every core call ever made.
        for _ in 0..<50 where !core.calls.contains(where: { $0.method == "shares.host_ticket" }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!core.calls.isEmpty)
        for call in core.calls {
            #expect(!call.json.contains(secret), "\(call.method) carried the link secret")
            #expect(call.params["secret"] == nil)
        }
        let access = try #require(core.calls.first { $0.method == "shares.create" }?.params["access"] as? String)
        #expect(access == ShareSecret(base64url: secret)?.keys(shareID: "k7f29q01").access,
                "access is derived from the secret and the proposed id")
        await controller.stopAll()
    }

    @Test func testQuitRevokesUntilQuitShares() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore()
        let controller = makeController(core: core, workspace: f.workspace)
        _ = try await controller.share(workspaceID: f.workspace.id, permission: .view, lifetime: .oneHour)
        _ = try await controller.share(workspaceID: f.workspace.id, permission: .type, lifetime: .untilQuit)
        let phone = try await controller.startPhoneHandoff(workspaceID: f.workspace.id)
        #expect(phone.oneTime && phone.permission == .type && phone.lifetime == .untilQuit)
        #expect(phone.claimUntil != nil)
        #expect(controller.active.count == 3)
        await controller.stopAll()
        #expect(controller.active.isEmpty)
        #expect(Set(core.revokedIDs()) == ["k7f29q02", "k7f29q03"], "1 h link stays valid; until-quit and QR are revoked")
    }

    @Test func testTakenShareIDRetriesWithFreshID() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore()
        core.takenIDs = ["k7f29q01"]
        let controller = makeController(core: core, workspace: f.workspace)
        let url = try await controller.share(workspaceID: f.workspace.id)
        let creates = core.calls.filter { $0.method == "shares.create" }
        #expect(creates.compactMap { $0.params["id"] as? String } == ["k7f29q01", "k7f29q02"])
        let fragment = try #require(url.fragment)
        let secret = try #require(ShareSecret(base64url: fragment))
        #expect(creates.map { $0.params["access"] as? String }
            == [secret.keys(shareID: "k7f29q01").access, secret.keys(shareID: "k7f29q02").access],
            "same secret, access re-derived for the fresh id")
        #expect(url.path == "/s/k7f2-9q02")
        await controller.stopAll()
    }

    @Test func testQuitCleanupRunsInsideMainActorTask() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), hosts = ShareFakeHosts(), store = ShareMemoryStore()
        let controller = makeController(core: core, workspace: f.workspace, store: store, hosts: hosts)
        _ = try await controller.share(workspaceID: f.workspace.id, permission: .view, lifetime: .oneHour)
        _ = try await controller.share(workspaceID: f.workspace.id, permission: .type, lifetime: .untilQuit)
        _ = try await controller.startPhoneHandoff(workspaceID: f.workspace.id)
        // `NSApp.reply(toApplicationShouldTerminate:)` runs inside main-actor tasks: quit cleanup starts there,
        // with the main thread blocked until it returns.
        await Task { @MainActor in controller.stopAllForTermination() }.value
        #expect(controller.active.isEmpty)
        #expect(Set(core.revokedIDs()) == ["k7f29q02", "k7f29q03"])
        #expect(hosts.made.map(\.stopCalls) == [["terminate:host_quit"], ["terminate:host_quit"], ["terminate:host_quit"]])
        #expect(store.shares.map(\.id) == ["k7f29q01"], "the 1 h link stays for the next launch")
    }

    @Test func testRevokeStopsHostAndForgetsLink() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), hosts = ShareFakeHosts(), store = ShareMemoryStore()
        let controller = makeController(core: core, workspace: f.workspace, store: store, hosts: hosts)
        _ = try await controller.share(workspaceID: f.workspace.id)
        #expect(store.shares.count == 1)
        #expect(await controller.revoke("k7f2-9q01"))
        #expect(hosts.host("k7f29q01")?.stopCalls == ["stop:revoked"])
        #expect(core.revokedIDs() == ["k7f29q01"])
        #expect(controller.active.isEmpty)
        #expect(store.shares.isEmpty, "a revoked link never resumes")
    }

    @Test func testLinkResumesAfterRelaunch() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), store = ShareMemoryStore()
        let first = makeController(core: core, workspace: f.workspace, store: store, hosts: ShareFakeHosts())
        let url = try await first.share(workspaceID: f.workspace.id, permission: .type, lifetime: .fifteenMinutes)
        first.stopAllForTermination()
        #expect(core.revokedIDs().isEmpty)
        let saved = try #require(store.shares.first)
        #expect(saved.workspaceID == f.workspace.id && saved.slot == "slot-k7f29q01")

        let hosts = ShareFakeHosts()
        let relaunched = makeController(core: core, workspace: f.workspace, store: store, hosts: hosts)
        let resumed = try #require(relaunched.active.first)
        #expect(resumed.url == url, "same id and secret: the old link works again")
        #expect(resumed.permission == .type && resumed.lifetime == .fifteenMinutes)
        let spec = try #require(hosts.made.first?.spec)
        #expect(spec.shareID == "k7f29q01" && spec.slot == "slot-k7f29q01")
        #expect(spec.secret.base64url == url.fragment)
        #expect(spec.expiresAt == saved.expiresAt)
        relaunched.stopAllForTermination()
    }

    @Test func testExpiredOrOrphanedPersistedLinksAreDropped() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), store = ShareMemoryStore(), hosts = ShareFakeHosts()
        let secret = ShareSecret.random().base64url
        store.shares = [
            PersistedShare(id: "aaaabbbb", slot: "s1", secret: secret, permission: .view, lifetime: .oneHour,
                           expiresAt: Date().addingTimeInterval(-5), workspaceID: f.workspace.id),
            PersistedShare(id: "ccccdddd", slot: "s2", secret: secret, permission: .view, lifetime: .oneHour,
                           expiresAt: Date().addingTimeInterval(600), workspaceID: UUID()),
        ]
        let controller = makeController(core: core, workspace: f.workspace, store: store, hosts: hosts)
        #expect(controller.active.isEmpty)
        #expect(hosts.made.isEmpty)
        #expect(store.shares.isEmpty)
        #expect(try await eventually { core.revokedIDs() == ["ccccdddd"] }, "a live link whose workspace is gone is revoked")
    }

    @Test func testSecretNeverInUserDefaults() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), store = ShareMemoryStore()
        let controller = makeController(core: core, workspace: f.workspace, store: store, hosts: ShareFakeHosts())
        let link = try await controller.share(workspaceID: f.workspace.id)
        let qr = try await controller.phoneHandoff(workspaceID: f.workspace.id)
        let secrets = [try #require(link.fragment), try #require(qr.fragment)]
        let defaults = String(describing: UserDefaults.standard.dictionaryRepresentation())
        for secret in secrets { #expect(!defaults.contains(secret)) }
        #expect(store.shares.map(\.secret) == [secrets[0]], "only the 1 h link is kept, and only in the store")
        controller.stopAllForTermination()
    }

    @Test func testExpiredShareLeavesTheList() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), hosts = ShareFakeHosts(), store = ShareMemoryStore()
        let sleeper = ShareManualSleeper()
        let controller = makeController(core: core, workspace: f.workspace, store: store, sleeper: sleeper, hosts: hosts)
        _ = try await controller.share(workspaceID: f.workspace.id)
        _ = try await controller.share(workspaceID: f.workspace.id, lifetime: .fifteenMinutes)
        #expect(try await eventually { sleeper.waiting == 2 })
        // The host ended on its own: the entry goes.
        hosts.host("k7f29q02")?.finish()
        #expect(try await eventually { controller.active.map(\.id) == ["k7f2-9q01"] })
        // expiresAt passed: the host gets bye(expired) and the link leaves list and store.
        sleeper.fireAll()
        #expect(try await eventually { controller.active.isEmpty })
        #expect(try await eventually { hosts.host("k7f29q01")?.stopCalls == ["stop:expired"] })
        #expect(store.shares.isEmpty)
    }

    @Test func testQRRenewsWhenUnclaimedCodeExpires() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), hosts = ShareFakeHosts()
        let controller = makeController(core: core, workspace: f.workspace, hosts: hosts)
        let sleeper = ShareManualSleeper()
        let model = ShellXPhoneHandoffModel(workspaceID: f.workspace.id, controller: controller, sleeper: sleeper)
        model.open()
        #expect(try await eventually { model.shareID == "k7f2-9q01" && model.qrImage != nil && sleeper.waiting == 1 })
        sleeper.fireAll()
        #expect(try await eventually { model.shareID == "k7f2-9q02" && model.qrImage != nil })
        #expect(core.revokedIDs() == ["k7f29q01"])
        #expect(hosts.host("k7f29q01")?.stopCalls == ["stop:revoked"])
        model.close()
        #expect(try await eventually { core.revokedIDs() == ["k7f29q01", "k7f29q02"] }, "closing revokes the unclaimed code")
    }

    @Test func testResumedShareStopsWhenServerRevokedIt() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), store = ShareMemoryStore()
        core.hostTicketError = "share_revoked"
        store.shares = [PersistedShare(id: "aaaabbbb", slot: "s1", secret: ShareSecret.random().base64url,
                                       permission: .view, lifetime: .oneHour,
                                       expiresAt: Date().addingTimeInterval(600), workspaceID: f.workspace.id)]
        // A real ShareHost: its host ticket is refused for good, so it stops instead of retrying.
        let controller = makeController(core: core, workspace: f.workspace, store: store)
        #expect(controller.active.map(\.id) == ["aaaa-bbbb"])
        #expect(try await eventually { controller.active.isEmpty }, "the ghost leaves the list")
        #expect(store.shares.isEmpty, "and the store")
        try await Task.sleep(for: .milliseconds(100))
        #expect(core.calls.filter { $0.method == "shares.host_ticket" }.count == 1, "no retry")
    }

    @Test func testResumeWaitsForSessionRestore() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), store = ShareMemoryStore(), hosts = ShareFakeHosts()
        let saved = PersistedShare(id: "aaaabbbb", slot: "s1", secret: ShareSecret.random().base64url,
                                   permission: .view, lifetime: .oneHour,
                                   expiresAt: Date().addingTimeInterval(600), workspaceID: f.workspace.id)
        store.shares = [saved]
        let session = ShareSession(signedIn: true, restored: false)
        session.workspaceExists = false // not restored yet
        let controller = makeController(core: core, workspace: f.workspace, store: store, hosts: hosts, session: session)
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.active.isEmpty && hosts.made.isEmpty)
        #expect(core.revokedIDs().isEmpty, "signed in before restore: nothing is revoked")
        #expect(store.shares == [saved])
        // Restore brings the workspace back, then reports done.
        session.workspaceExists = true
        session.restored.send(true)
        #expect(controller.active.map(\.id) == ["aaaa-bbbb"])
        #expect(hosts.made.first?.spec.slot == "s1")
        try await Task.sleep(for: .milliseconds(50))
        #expect(core.revokedIDs().isEmpty)
        controller.stopAllForTermination()
    }

    @Test func testSignOutStopsSharesAndKeepsAccountsApart() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), store = ShareMemoryStore(), hosts = ShareFakeHosts()
        let session = ShareSession()
        let controller = makeController(core: core, workspace: f.workspace, store: store, hosts: hosts, session: session)
        _ = try await controller.share(workspaceID: f.workspace.id)
        session.signedIn.send(false)
        #expect(controller.active.isEmpty)
        #expect(try await eventually { hosts.made.first?.stopCalls == ["stop:host_quit"] })
        #expect(store.shares.count == 1, "account A's link stays under account A")
        // Account B signs in: A's links are not touched.
        session.account = "user-b"
        session.signedIn.send(true)
        #expect(controller.active.isEmpty)
        #expect(hosts.made.count == 1)
        #expect(store.byAccount["user-b"] ?? [] == [])
        controller.stopAllForTermination()
        #expect(store.shares.count == 1)
    }

    @Test func testQuitDuringRevokeStillRevokes() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore(), hosts = ShareFakeHosts()
        let controller = makeController(core: core, workspace: f.workspace, hosts: hosts)
        _ = try await controller.share(workspaceID: f.workspace.id)
        let gate = ShareStopGate()
        hosts.made.first?.stopGate = gate
        let revoking = Task { await controller.revoke("k7f2-9q01") }
        #expect(try await eventually { gate.isWaiting })
        controller.stopAllForTermination() // quit while the host is still sending its bye
        #expect(core.revokedIDs() == ["k7f29q01"], "the in-flight revoke is done by the quit path")
        gate.open()
        _ = await revoking.value
    }

    @Test func testSignedOutShareMakesNoCoreCall() async throws {
        let f = try makeFixture()
        defer { f.browser.close() }
        let core = ShareFakeCore()
        let controller = makeController(core: core, workspace: f.workspace, signedIn: false)
        await #expect(throws: ShellXShareError.notSignedIn) {
            _ = try await controller.share(workspaceID: f.workspace.id)
        }
        #expect(ShellXSharePopoverModel(workspaceID: f.workspace.id, controller: controller).needsSignIn)
        #expect(core.calls.isEmpty)
    }

    @Test func testGateOffHidesEntrypoints() throws {
        defer { ShellXShareGate.overrideForTesting = nil }
        #expect(!ShellXShareGate.isEnabled(flag: false, remoteMachines: true, environment: [:]))
        #expect(ShellXShareGate.isEnabled(flag: true, remoteMachines: true, environment: [:]))
        // Ruling R1b: no remote-machines gate, no share entrypoints (the sign-in path lives there).
        #expect(!ShellXShareGate.isEnabled(flag: true, remoteMachines: false, environment: [:]))
        #expect(!ShellXShareGate.isEnabled(flag: false, remoteMachines: false,
                                           environment: [ShellXShareGate.environmentKey: "1"]))
        #expect(ShellXShareGate.isEnabled(flag: false, remoteMachines: true,
                                          environment: [ShellXShareGate.environmentKey: "1"]))
        let shareTitles = [ShellXShareActions.title(.share), ShellXShareActions.title(.phone)]

        ShellXShareGate.overrideForTesting = false
        #expect(ShellXShareActions.menuEntries.isEmpty)
        #expect(!ShellXTitlebarAccessoryViewController().rootView.showsShare)
        let offTitles = try menuTitles()
        #expect(shareTitles.allSatisfy { !offTitles.contains($0) })

        ShellXShareGate.overrideForTesting = true
        #expect(ShellXShareActions.menuEntries == [.share, .phone])
        #expect(ShellXTitlebarAccessoryViewController().rootView.showsShare)
        let onTitles = try menuTitles()
        #expect(shareTitles.allSatisfy { onTitles.contains($0) })
    }

    private func menuTitles() throws -> [String] {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let commands = SidebarWorkspaceRowCommands(
            tab: workspace, tabManager: manager, notificationStore: nil, index: 0,
            contextMenuWorkspaceIds: [workspace.id], remoteContextMenuWorkspaceIds: [],
            allRemoteContextMenuTargetsConnecting: false, allRemoteContextMenuTargetsDisconnected: false,
            contextMenuPinState: nil, workspaceGroupMenuSnapshot: WorkspaceGroupMenuSnapshot(items: []),
            colorScheme: .dark, refreshSnapshot: {}, readSelectedTabIds: { [] }, writeSelectedTabIds: { _ in },
            readLastSelectionIndex: { nil }, writeLastSelectionIndex: { _ in }, setSelectionToTabs: {},
            snapshotProvider: { nil })
        let menu = commands.makeContextMenu(onOpen: {}, onClose: {}, beginInlineRename: {})
        return menu.items.map(\.title)
    }
}
