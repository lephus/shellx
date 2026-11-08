import AppKit
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

@MainActor
@Suite("ShellX Link terminal view source", .serialized, .timeLimit(.minutes(1)))
struct ShellXLinkTerminalViewSourceTests {
    private let terminalID = UUID()
    private let workspaceID = UUID()
    private let surfaceID = UUID()

    private func notOpened(_ result: TerminalViewOpenResult) -> TerminalViewOpenOutcome? {
        if case .notOpened(let outcome) = result { return outcome }
        return nil
    }

    private func makeSource(_ fake: FakeLinkMac, registry: RecordingFrameSinkRegistry? = nil) -> ShellXLinkTerminalViewSource {
        ShellXLinkTerminalViewSource(
            mac: fake.mac, frameSinks: registry ?? RecordingFrameSinkRegistry(), notificationCenter: NotificationCenter()
        )
    }

    private func listedFake() -> FakeLinkMac {
        let fake = FakeLinkMac()
        fake.listed[terminalID] = workspaceID
        fake.surfaces[terminalID] = surfaceID
        return fake
    }

    @Test func aBlockedMacRefusesTheOpen() async {
        let fake = listedFake()
        fake.blocked = true
        let result = await makeSource(fake).openView(terminalId: terminalID.uuidString, cols: 46, rows: 30)
        #expect(notOpened(result) == .refused)
        #expect(fake.prepares.isEmpty)
    }

    @Test func anIdThatIsNotListedIsNotFound() async {
        let fake = listedFake()
        let source = makeSource(fake)
        let named = await source.openView(terminalId: "ws-a", cols: 46, rows: 30)
        let unlisted = await source.openView(terminalId: UUID().uuidString, cols: 46, rows: 30)
        #expect(notOpened(named) == .notFound && notOpened(unlisted) == .notFound)
        #expect(fake.prepares.isEmpty)
    }

    @Test func aListedTerminalThatCannotBePreparedFails() async {
        let fake = listedFake()
        fake.surfaces = [:]
        let result = await makeSource(fake).openView(terminalId: terminalID.uuidString, cols: 46, rows: 30)
        #expect(notOpened(result) == .failed)
    }

    @Test func aListedTerminalOpensAndJoinsTheSizing() async {
        let fake = listedFake()
        let registry = RecordingFrameSinkRegistry()
        let source = makeSource(fake, registry: registry)
        let result = await source.openView(terminalId: terminalID.uuidString, cols: 46, rows: 30)
        guard case .opened(let view) = result else {
            Issue.record("not opened")
            return
        }
        #expect(fake.prepares == [FakeLinkMac.Prepare(workspace: workspaceID, terminal: terminalID)])
        #expect(fake.attaches.count == 1 && fake.attaches[0].cols == 46 && fake.attaches[0].rows == 30)
        #expect(fake.attaches.first?.clientID.hasPrefix(TerminalController.shellXLinkSizingClientIDPrefix) == true)
        #expect(source.openViewCount == 1)
        #expect(registry.sinks.count == 1 && registry.sinks.first === (view as AnyObject))
        await view.close()
    }

    @Test func eachOpenIsItsOwnParticipant() async {
        let fake = listedFake()
        let source = makeSource(fake)
        let first = await source.openView(terminalId: terminalID.uuidString, cols: 46, rows: 30)
        let second = await source.openView(terminalId: terminalID.uuidString, cols: 46, rows: 30)
        #expect(fake.attaches.count == 2 && fake.attaches[0].clientID != fake.attaches[1].clientID)
        #expect(fake.attaches.allSatisfy { $0.clientID.hasPrefix(TerminalController.shellXLinkSizingClientIDPrefix) })
        for case .opened(let view) in [first, second] { await view.close() }
    }

    @Test func aViewEndsGoneWhenItsTerminalLeavesTheList() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let terminal = try ScrollbackTestTerminal()
            defer { terminal.close() }
            try await terminal.launch()
            try await terminal.setGrid(columns: 20, rows: 5)
            let fake = listedFake()
            fake.terminal = terminal
            fake.surfaces[terminalID] = terminal.surface.id
            let source = makeSource(fake)
            let result = await source.openView(terminalId: terminalID.uuidString, cols: 20, rows: 5)
            guard case .opened(let opened) = result, let view = opened as? ShellXLinkTerminalView else {
                Issue.record("not opened")
                return
            }
            guard case .frame(let frame) = try await view.nextEvent() else {
                Issue.record("no first frame")
                return
            }
            #expect(frame.head.kind == .snapshot)
            fake.listed[terminalID] = nil
            fake.fireListChange()
            let ended = try await view.nextEvent()
            #expect(ended == .ended(.gone))
            await opened.close()
        }
    }

    @Test func theListIsWatchedOnlyWhileAViewIsOpen() async {
        let fake = listedFake()
        let source = makeSource(fake)
        #expect(fake.listenerCount == 0)
        let first = await source.openView(terminalId: terminalID.uuidString, cols: 46, rows: 30)
        #expect(fake.listenerCount == 1)
        let second = await source.openView(terminalId: terminalID.uuidString, cols: 46, rows: 30)
        #expect(fake.listenerCount == 1)
        for case .opened(let view) in [first, second] { await view.close() }
        #expect(fake.listenerCount == 0 && source.openViewCount == 0)
    }

    @Test func liveSourceOpensAListedTerminalAndJoinsItsSizing() async throws {
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
            let registry = RecordingFrameSinkRegistry()
            let source = ShellXLinkTerminalViewSource(
                mac: .live(workspaces: ShellXLinkWorkspaceSource()), frameSinks: registry, notificationCenter: NotificationCenter()
            )

            let unlisted = await source.openView(terminalId: UUID().uuidString, cols: 46, rows: 30)
            #expect(notOpened(unlisted) == .notFound)
            let result = await source.openView(terminalId: panelID.uuidString, cols: 46, rows: 30)
            guard case .opened(let view) = result else {
                Issue.record("not opened")
                return
            }
            let participants = controller.terminalSharing.snapshot(for: panelID)?.state.participants
                .map(\.participant.id) ?? []
            #expect(participants.filter { $0.hasPrefix("mobile:shellx-link-") }.count == 1)
            await view.close()
            let after = controller.terminalSharing.snapshot(for: panelID)?.state.participants.map(\.participant.id) ?? []
            #expect(!after.contains { $0.hasPrefix("mobile:shellx-link-") })
        }
    }
}
