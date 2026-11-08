import AppKit
import CmuxSettings
import CmuxSidebar
import Foundation
import ShellXLinkCore
import ShellXLinkSession
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

private struct NoFeed: AgentFeedSource {
    func snapshot() async -> (revision: Int, pending: [PendingItem]) { (0, []) }
    func changes() -> AsyncStream<(revision: Int, added: [PendingItem], resolved: [String])> {
        AsyncStream { $0.finish() }
    }
    func reply(requestId: String, decision: LinkDecision) async -> ReplyOutcome { .unknown }
}

private actor FakeTerminalCreator: TerminalCreator {
    func createTerminal(workspaceId: String) async -> (outcome: WorkspaceControlOutcome, terminalId: String?) {
        (.ok, "t-new")
    }
}

/// The pushes of one client, in arrival order.
@MainActor
private final class PushCollector {
    private(set) var pushes: [TerminalViewPush] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<TerminalViewPush>) {
        task = Task { @MainActor [weak self] in
            for await push in stream { self?.pushes.append(push) }
        }
    }

    deinit { task?.cancel() }

    /// The screen of the view opened last for `terminalId`: a fresh assembler over the frames after its `.opened`.
    func screen(terminalId: String) -> TerminalScreen {
        var assembler = TerminalFrameAssembler()
        var screen = TerminalScreen()
        var started = false
        let lastOpened = pushes.lastIndex { $0 == .opened(terminalId: terminalId) }
        for (index, push) in pushes.enumerated() {
            guard let lastOpened, index >= lastOpened else { continue }
            switch push {
            case .opened(let id) where id == terminalId:
                assembler = TerminalFrameAssembler()
                started = true
            case .frame(let id, let part) where id == terminalId && started:
                if let frame = assembler.receive(part).frame { screen.apply(frame) }
            default:
                break
            }
        }
        return screen
    }

    func ended(terminalId: String) -> TerminalViewEndReason? {
        for push in pushes.reversed() {
            if case .ended(let id, let reason) = push, id == terminalId { return reason }
        }
        return nil
    }

    func eventually(_ condition: @MainActor (PushCollector) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if condition(self) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition(self)
    }
}

@MainActor
@Suite("ShellX Link terminal sessions", .serialized, .timeLimit(.minutes(2)))
struct ShellXLinkTerminalSessionTests {
    private func sources(
        views: (any TerminalViewSource)?, creator: (any TerminalCreator)?
    ) -> ShellXLinkHostController.Sources {
        ShellXLinkHostController.Sources(feed: NoFeed(), terminalViews: views, terminalCreator: creator)
    }

    private struct Session {
        let host: LinkHost
        let client: LinkClient
        let phoneKey: NoiseStaticKey
        let serving: Task<Void, Never>
    }

    private func connect(_ sources: ShellXLinkHostController.Sources) async throws -> Session {
        let hostKey = NoiseStaticKey()
        let phoneKey = NoiseStaticKey()
        let trusted: Set<Data> = [phoneKey.publicKey]
        let host = ShellXLinkHostController.makeLinkHost(
            key: hostKey, trustedClients: { trusted }, sources: sources, hostVersion: "test", machineName: "Mac"
        )
        let (hostEnd, phoneEnd) = makeInMemoryCircuitPair()
        let serving = Task { await host.serve(hostEnd) }
        let client = try await LinkClient.connect(
            phoneEnd, key: phoneKey, hostKey: hostKey.publicKey, clientVersion: "test", deviceName: "probe"
        )
        return Session(host: host, client: client, phoneKey: phoneKey, serving: serving)
    }

    private func finish(_ session: Session) async {
        await session.client.close()
        session.serving.cancel()
    }

    @Test func theLinkHostOffersTerminalViewsAndCreationOnlyWithTheirSources() async throws {
        let fake = FakeLinkMac()
        let views = ShellXLinkTerminalViewSource(
            mac: fake.mac, frameSinks: RecordingFrameSinkRegistry(), notificationCenter: NotificationCenter()
        )
        let with = try await connect(sources(views: views, creator: FakeTerminalCreator()))
        #expect(with.client.hostFeatures.isSuperset(of: ["terminal_view", "terminal_create"]))
        await finish(with)
        let without = try await connect(sources(views: nil, creator: nil))
        #expect(!without.client.hostFeatures.contains("terminal_view"))
        #expect(!without.client.hostFeatures.contains("terminal_create"))
        await finish(without)
    }

    /// A launched 20x5 terminal listed as `terminalID` in `workspaceID`, behind a real host and client.
    private func withRig(
        _ body: @MainActor (
            ScrollbackTestTerminal, FakeLinkMac, RecordingFrameSinkRegistry, TestPolicy, Session, PushCollector
        ) async throws -> Void
    ) async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let terminal = try ScrollbackTestTerminal()
            defer { terminal.close() }
            try await terminal.launch()
            try await terminal.setGrid(columns: 20, rows: 5)
            try terminal.output("\u{1b}c")
            let fake = FakeLinkMac()
            fake.terminal = terminal
            fake.listed[terminal.surface.id] = UUID()
            fake.surfaces[terminal.surface.id] = terminal.surface.id
            let registry = RecordingFrameSinkRegistry()
            let policy = TestPolicy()
            let views = ShellXLinkTerminalViewSource(mac: fake.mac, frameSinks: registry, notificationCenter: policy.center)
            let session = try await connect(sources(views: views, creator: FakeTerminalCreator()))
            let pushes = PushCollector(session.client.terminalPushes)
            try await body(terminal, fake, registry, policy, session, pushes)
            await finish(session)
        }
    }

    @Test func thePhoneSeesTheTerminalAndTypesIntoIt() async throws {
        try await withRig { terminal, _, _, _, session, pushes in
            let id = terminal.surface.id.uuidString
            try terminal.output("\u{1b}chello-2b\r\n")
            try await terminal.waitForScreen(containing: "hello-2b")
            let opened = try await session.client.openTerminalView(terminalId: id, cols: 20, rows: 5)
            #expect(opened == .ok)
            #expect(await pushes.eventually { $0.screen(terminalId: id).screenText().contains("hello-2b") })
            try await session.client.sendTerminalInput(terminalId: id, units: [.text("ls"), .key(.enter, mods: [])])
            let typed = await terminal.inputBytes(until: { $0.count >= 3 })
            #expect(typed == Data("ls\r".utf8))
            let created = try await session.client.createTerminal(workspaceId: UUID().uuidString)
            #expect(created.outcome == .ok && created.terminalId == "t-new")
        }
    }

    @Test func inputForAnotherTerminalReachesNothing() async throws {
        try await withRig { terminal, _, _, _, session, pushes in
            let id = terminal.surface.id.uuidString
            let other = UUID().uuidString
            #expect(try await session.client.openTerminalView(terminalId: id, cols: 20, rows: 5) == .ok)
            try await session.client.sendTerminalInput(terminalId: other, units: [.text("x")])
            #expect(await pushes.eventually { $0.ended(terminalId: other) == .notOpen })
            let leaked = try await terminal.inputBytesBeforeBarrier()
            #expect(leaked.isEmpty)
        }
    }

    @Test func unpairingClosesThePhonesView() async throws {
        try await withRig { terminal, fake, registry, _, session, _ in
            let id = terminal.surface.id.uuidString
            #expect(try await session.client.openTerminalView(terminalId: id, cols: 20, rows: 5) == .ok)
            await session.host.disconnect(clientKey: session.phoneKey.publicKey)
            let deadline = ContinuousClock.now + .seconds(5)
            while ContinuousClock.now < deadline,
                  !(fake.sizings.last?.calls.last == .detach && registry.sinks.isEmpty) {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(fake.sizings.last?.calls.last == .detach)
            #expect(registry.sinks.isEmpty)
        }
    }

    @Test func deviceManagementMidSessionRefusesTheViewAndNewOpens() async throws {
        try await withRig { terminal, fake, _, policy, session, pushes in
            let id = terminal.surface.id.uuidString
            #expect(try await session.client.openTerminalView(terminalId: id, cols: 20, rows: 5) == .ok)
            fake.blocked = true
            policy.change(blocked: true)
            #expect(await pushes.eventually { $0.ended(terminalId: id) == .refused })
            #expect(try await session.client.openTerminalView(terminalId: id, cols: 20, rows: 5) == .refused)
        }
    }

    @Test func viewingAndTypingNeverChangeTheMacSelection() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            _ = NSApplication.shared
            let previousAppDelegate = AppDelegate.shared
            let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
            let app = AppDelegate()
            AppDelegate.shared = app
            let windowID = UUID()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 320), styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(windowID.uuidString)")
            let manager = TabManager(autoWelcomeIfNeeded: false)
            app.registerMainWindow(
                window, windowId: windowID, tabManager: manager, sidebarState: SidebarState(),
                sidebarSelectionState: SidebarSelectionState(), fileExplorerState: FileExplorerState()
            )
            TerminalController.shared.setActiveTabManager(manager)
            let controller = TerminalController.shared
            defer {
                controller.debugResetMobileViewportReportsForTesting()
                controller.resetLocalSizingHosts()
                app.unregisterMainWindowContextForTesting(windowId: windowID)
                window.orderOut(nil)
                controller.setActiveTabManager(previousManager)
                manager.tabs.forEach { $0.teardownAllPanels() }
                AppDelegate.shared = previousAppDelegate
            }
            let workspace = try #require(manager.tabs.first)
            let panelID = try #require(workspace.focusedPanelId)
            let views = ShellXLinkTerminalViewSource(
                mac: .live(workspaces: ShellXLinkWorkspaceSource()), frameSinks: RecordingFrameSinkRegistry(),
                notificationCenter: NotificationCenter()
            )
            let session = try await connect(sources(views: views, creator: nil))
            func selection() -> [String] {
                let panes = workspace.bonsplitController.allPaneIds.map {
                    "\(String(describing: workspace.bonsplitController.selectedTab(inPane: $0)?.id))"
                }
                return panes + [
                    "\(String(describing: manager.selectedTabId))",
                    "\(String(describing: NSApp.keyWindow?.windowNumber))",
                    "\(window.isKeyWindow)",
                ]
            }
            let before = selection()
            let id = panelID.uuidString
            #expect(try await session.client.openTerminalView(terminalId: id, cols: 20, rows: 5) == .ok)
            try await session.client.sendTerminalInput(terminalId: id, units: [.text("x"), .key(.enter, mods: [])])
            try await session.client.resizeTerminalView(terminalId: id, cols: 30, rows: 8)
            try await session.client.closeTerminalView(terminalId: id)
            try await Task.sleep(for: .milliseconds(200))
            #expect(selection() == before)
            await finish(session)
        }
    }
}
