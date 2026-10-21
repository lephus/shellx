import AppKit
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

/// Records every core call and answers the share methods like the fake API.
final class ShareFakeCore: ShellXCoreCalling, @unchecked Sendable {
    struct Call { let method: String; let json: String; let params: [String: Any] }
    private let lock = NSLock()
    private var recorded: [Call] = []
    private var issued = 0

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }

    /// The id the next `shares.create` assigns; `newShareID` proposes the same one.
    func nextID() -> String {
        lock.lock(); defer { lock.unlock() }
        issued += 1
        return String(format: "k7f29q%02d", issued)
    }

    private var lastIssued: String {
        lock.lock(); defer { lock.unlock() }
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
            let claim = (params["one_time"] as? Bool) == true ? "\(now + 120)" : "null"
            reply = #"{"ok":{"id":"\#(lastIssued)","slot":"slot-\#(lastIssued)","expires_at_unix":\#(now + 3600),"claim_until_unix":\#(claim)}}"#
        case "shares.host_ticket":
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

    func send(text: String) async throws { lock.lock(); sentText.append(text); lock.unlock() }
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
        lock.lock(); opened.append(url); lock.unlock()
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

@MainActor
@Suite(.serialized)
struct ShellXShareTests {
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
                                workspace: Workspace?, signedIn: Bool = true) -> ShellXShareController {
        let env = ShellXShareEnvironment(
            core: ShellXCoreClient(core), sockets: sockets,
            isSignedIn: { signedIn }, presentSignIn: {},
            source: { [weak workspace] id in
                guard let workspace, workspace.id == id else { return nil }
                return WorkspaceShareSource(workspace: workspace, io: ShareFakeTerminalIO())
            },
            newShareID: { core.nextID() })
        return ShellXShareController(environment: env)
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
        #expect(access == ShareSecret(base64url: secret)?.keys(shareID: "k7f29q01").access)
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
        #expect(!ShellXShareGate.isEnabled(flag: false, environment: [:]))
        #expect(ShellXShareGate.isEnabled(flag: true, environment: [:]))
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
