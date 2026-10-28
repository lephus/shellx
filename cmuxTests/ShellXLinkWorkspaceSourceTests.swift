import AppKit
import CMUXAgentLaunch
import CmuxAgentChat
import CmuxMobileHost
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

/// ShellX Link's `WorkspaceSource` and `WorkspaceControl` over the Mac's main windows: which workspaces a phone
/// lists, the numbered changes it is pushed, and how making, renaming and closing a workspace answer.
@MainActor
@Suite("ShellX Link workspace source", .serialized, .timeLimit(.minutes(1)))
struct ShellXLinkWorkspaceSourceTests {
    private static func workspace(_ name: String, order: Int, title: String? = nil) -> LinkWorkspace {
        LinkWorkspace(
            workspaceId: "ws-\(name)", title: title ?? name, order: order, directory: "~/\(name)", branch: "main",
            ports: [3000], terminals: [LinkTerminal(terminalId: "t-\(name)", title: "zsh", order: 0, selected: true)]
        )
    }

    /// A source over a fake Mac: a list, control calls and a change signal the test drives.
    private static func makeSource() -> (FakeMac, ShellXLinkWorkspaceSource) {
        let mac = FakeMac()
        let source = ShellXLinkWorkspaceSource(
            snapshot: { mac.workspaces }, control: mac.control, changeSignal: { mac.signal($0) }
        )
        return (mac, source)
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    /// Waits until `count` stops moving for 500 ms (twice the live signal's 250 ms throttle), so what follows is not
    /// mixed up with an earlier change's trailing signal.
    private static func waitUntilQuiet(_ count: @MainActor () -> Int) async {
        for _ in 0..<20 {
            let before = count()
            try? await Task.sleep(nanoseconds: 500_000_000)
            if count() == before { return }
        }
    }

    private static func makeMainWindow(id: UUID) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(id.uuidString)")
        return window
    }

    // MARK: - List and changes

    @Test func listMapsSnapshot() async {
        let (mac, source) = Self.makeSource()
        let expected = [Self.workspace("a", order: 0), Self.workspace("b", order: 1)]
        mac.workspaces = expected

        let list = await source.workspaces()

        #expect(list.revision == 0)
        #expect(list.workspaces == expected)
    }

    @Test func changeBumpsRevisionOnce() async throws {
        let (mac, source) = Self.makeSource()
        let a = Self.workspace("a", order: 0)
        mac.workspaces = [a, Self.workspace("b", order: 1)]
        var changes = source.workspaceChanges().makeAsyncIterator()
        #expect(await Self.waitUntil { source.subscriberCount == 1 })
        #expect(await source.workspaces().revision == 0)

        let renamed = Self.workspace("b", order: 1, title: "api")
        mac.workspaces = [a, renamed]
        mac.fireChange()

        let change = try #require(await changes.next())
        #expect(change.revision == 1)
        #expect(change.upserted == [renamed])
        #expect(change.removed.isEmpty)

        // A signal with nothing changed sends no frame: the next change is numbered 2.
        mac.fireChange()
        let renamedAgain = Self.workspace("b", order: 1, title: "web")
        mac.workspaces = [a, renamedAgain]
        mac.fireChange()

        let next = try #require(await changes.next())
        #expect(next.revision == 2)
        #expect(next.upserted == [renamedAgain])
        let now = await source.workspaces()
        #expect(now.revision == 2)
        #expect(now.workspaces == [a, renamedAgain])
    }

    @Test func removedWorkspaceListedInRemoved() async throws {
        let (mac, source) = Self.makeSource()
        let a = Self.workspace("a", order: 0)
        mac.workspaces = [a, Self.workspace("b", order: 1)]
        var changes = source.workspaceChanges().makeAsyncIterator()
        #expect(await Self.waitUntil { source.subscriberCount == 1 })
        let before = await source.workspaces()

        mac.workspaces = [a]
        mac.fireChange()

        let change = try #require(await changes.next())
        #expect(change.revision == before.revision + 1)
        #expect(change.removed == ["ws-b"])
        #expect(change.upserted.isEmpty)
        #expect(await source.workspaces().workspaces == [a])
    }

    /// The change signal runs only while a phone listens: listing alone attaches nothing.
    @Test func changeSignalAttachedOnlyWhileSubscribed() async {
        let (mac, source) = Self.makeSource()
        _ = await source.workspaces()
        #expect(mac.attachCount == 0)

        let consumer = Task { for await _ in source.workspaceChanges() {} }
        #expect(await Self.waitUntil { mac.isAttached })
        #expect(mac.attachCount == 1)

        consumer.cancel()
        _ = await consumer.value
        #expect(await Self.waitUntil { !mac.isAttached && source.subscriberCount == 0 })
    }

    /// The live list over two real main windows: one window's local workspaces, then the other's, each in sidebar
    /// order, numbered without a gap; a remote workspace is not listed.
    @Test func twoWindowsListedInOrder() throws {
        _ = NSApplication.shared
        let previousAppDelegate = AppDelegate.shared
        let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
        let app = AppDelegate()
        AppDelegate.shared = app
        defer {
            TerminalController.shared.setActiveTabManager(previousManager)
            AppDelegate.shared = previousAppDelegate
        }
        let windowAId = UUID(), windowBId = UUID()
        let windowA = Self.makeMainWindow(id: windowAId), windowB = Self.makeMainWindow(id: windowBId)
        let managerA = TabManager(), managerB = TabManager()
        defer {
            app.unregisterMainWindowContextForTesting(windowId: windowAId)
            app.unregisterMainWindowContextForTesting(windowId: windowBId)
            windowA.orderOut(nil)
            windowB.orderOut(nil)
        }
        app.registerMainWindow(
            windowA, windowId: windowAId, tabManager: managerA, sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState(), fileExplorerState: FileExplorerState()
        )
        app.registerMainWindow(
            windowB, windowId: windowBId, tabManager: managerB, sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState(), fileExplorerState: FileExplorerState()
        )
        _ = try #require(managerA.addWorkspaceIfActive(select: false, autoWelcomeIfNeeded: false, autoRefreshMetadata: false))
        let remote = try #require(
            managerB.addWorkspaceIfActive(select: false, autoWelcomeIfNeeded: false, autoRefreshMetadata: false)
        )
        remote.isRemoteTmuxMirror = true
        defer { remote.isRemoteTmuxMirror = false }

        let rows = ShellXLinkWorkspaceSource.liveWorkspaces()

        let idsA = managerA.tabs.map(\.id.uuidString)
        let idsB = managerB.tabs.filter { $0 !== remote }.map(\.id.uuidString)
        let ids = rows.map(\.workspaceId)
        #expect(idsA.count == 2 && idsB.count == 1)
        #expect(ids == idsA + idsB || ids == idsB + idsA)
        #expect(rows.map(\.order) == Array(0..<rows.count))
        #expect(!ids.contains(remote.id.uuidString))

        let first = try #require(managerA.tabs.first)
        let panel = try #require(first.focusedTerminalPanel)
        let row = try #require(rows.first { $0.workspaceId == first.id.uuidString })
        #expect(row.title == first.title)
        #expect(row.terminals.map(\.terminalId) == [panel.id.uuidString])
        #expect(row.terminals.first?.order == 0)
        #expect(row.terminals.first?.selected == true)
    }

    /// The live change signal follows the main windows and their workspaces: a workspace added in a window, a window
    /// opened later, a workspace added there, and a new git branch (kept in the sidebar metadata model, which
    /// `objectWillChange` does not cover) each fire it.
    @Test func liveSignalFollowsWindowsAndWorkspaces() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            _ = NSApplication.shared
            let previousAppDelegate = AppDelegate.shared
            let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
            let app = AppDelegate()
            AppDelegate.shared = app
            defer {
                TerminalController.shared.setActiveTabManager(previousManager)
                AppDelegate.shared = previousAppDelegate
            }
            let windowAId = UUID(), windowBId = UUID()
            let windowA = Self.makeMainWindow(id: windowAId), windowB = Self.makeMainWindow(id: windowBId)
            let managerA = TabManager(), managerB = TabManager()
            defer {
                app.unregisterMainWindowContextForTesting(windowId: windowAId)
                app.unregisterMainWindowContextForTesting(windowId: windowBId)
                windowA.orderOut(nil)
                windowB.orderOut(nil)
            }
            app.registerMainWindow(
                windowA, windowId: windowAId, tabManager: managerA, sidebarState: SidebarState(),
                sidebarSelectionState: SidebarSelectionState(), fileExplorerState: FileExplorerState()
            )
            let fired = Counter()
            let stop = ShellXLinkWorkspaceSource.liveChangeSignal { fired.count += 1 }
            defer { stop() }

            _ = try #require(
                managerA.addWorkspaceIfActive(select: false, autoWelcomeIfNeeded: false, autoRefreshMetadata: false)
            )
            #expect(await Self.waitUntil { fired.count > 0 })

            var seen = fired.count
            app.registerMainWindow(
                windowB, windowId: windowBId, tabManager: managerB, sidebarState: SidebarState(),
                sidebarSelectionState: SidebarSelectionState(), fileExplorerState: FileExplorerState()
            )
            #expect(await Self.waitUntil { fired.count > seen })
            seen = fired.count
            _ = try #require(
                managerB.addWorkspaceIfActive(select: false, autoWelcomeIfNeeded: false, autoRefreshMetadata: false)
            )
            #expect(await Self.waitUntil { fired.count > seen })

            // A `git checkout` in the same directory changes only the branch.
            let first = try #require(managerA.tabs.first)
            await Self.waitUntilQuiet { fired.count }
            seen = fired.count
            first.gitBranch = SidebarGitBranchState(branch: "feature/phone", isDirty: false)
            #expect(await Self.waitUntil { fired.count > seen })
        }
    }

    /// A terminal names the Claude Code session running in it: a live Claude session, not an ended one or
    /// another agent's.
    @Test func terminalCarriesLiveClaudeSession() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-link-workspaces-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let service = AgentChatTranscriptService(
            registry: AgentChatSessionRegistry(hookStore: AgentChatHookSessionStore(homeDirectory: home)),
            resolver: AgentChatTranscriptResolver(homeDirectory: home, environment: [:]),
            hasEventSubscribers: { false },
            emitEventPayload: { _ in }
        )
        let live = UUID().uuidString, ended = UUID().uuidString, codex = UUID().uuidString
        let liveSurface = UUID(), endedSurface = UUID(), codexSurface = UUID()
        func event(
            _ sessionID: String, _ name: WorkstreamEvent.HookEventName, source: String = "claude", surface: UUID
        ) -> WorkstreamEvent {
            WorkstreamEvent(
                sessionId: sessionID, hookEventName: name, source: source, surfaceId: surface.uuidString,
                transcriptPath: nil, cwd: "/Users/example/project", receivedAt: Date()
            )
        }
        service.noteHookEvent(event(live, .sessionStart, surface: liveSurface))
        service.noteHookEvent(event(ended, .sessionStart, surface: endedSurface))
        service.noteHookEvent(event(ended, .sessionEnd, surface: endedSurface))
        service.noteHookEvent(event(codex, .sessionStart, source: "codex", surface: codexSurface))

        let byTerminal = ShellXLinkWorkspaceSource.sessionIDsByTerminal(service.sessionRecords(workspaceID: nil))

        #expect(byTerminal == [liveSurface: live])
    }

    // MARK: - Control

    @Test func createAnswersNewWorkspaceId() async {
        let (mac, source) = Self.makeSource()
        mac.createResult = .ok(
            ["created_workspace_id": "ws-new", "workspaces": [Any](), "groups": [Any]()] as [String: Any]
        )

        let created = await source.createWorkspace()
        #expect(created.outcome == .ok)
        #expect(created.workspaceId == "ws-new")

        mac.createResult = .err(code: "internal_error", message: "Failed to create workspace", data: nil)
        let failed = await source.createWorkspace()
        #expect(failed.outcome == .failed)
        #expect(failed.workspaceId == nil)
        #expect(mac.creates == 2)
    }

    @Test func renameSanitizesTitle() async {
        let (mac, source) = Self.makeSource()
        mac.workspaces = [Self.workspace("a", order: 0)]

        #expect(await source.renameWorkspace(workspaceId: "ws-a", title: "  a\u{0007}b\n  ") == .ok)
        #expect(await source.renameWorkspace(workspaceId: "ws-a", title: String(repeating: "x", count: 200)) == .ok)
        #expect(mac.renames.map(\.title) == ["ab", String(repeating: "x", count: 128)])
        #expect(mac.renames.map(\.workspaceId) == ["ws-a", "ws-a"])

        // Nothing left once cleaned: failed, and the Mac is not asked.
        #expect(await source.renameWorkspace(workspaceId: "ws-a", title: "  \n ") == .failed)
        #expect(mac.renames.count == 2)

        // Characters, not bytes, are counted, and a joined emoji keeps its joiners.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(ShellXLinkWorkspaceSource.sanitizedTitle("Tiếng Việt \(family)\u{2028}") == "Tiếng Việt \(family)")
        #expect(ShellXLinkWorkspaceSource.sanitizedTitle(String(repeating: "ế", count: 200)).count == 128)
    }

    @Test func closeLastWorkspaceRefused() async {
        let (mac, source) = Self.makeSource()
        mac.workspaces = [Self.workspace("a", order: 0)]
        mac.closeResult = .err(code: "protected", message: "This workspace can't be closed right now.", data: nil)

        #expect(await source.closeWorkspace(workspaceId: "ws-a") == .refused)
        #expect(mac.closes == ["ws-a"])
    }

    @Test(arguments: [
        ("not_found", WorkspaceControlOutcome.notFound),
        ("confirmation_required", WorkspaceControlOutcome.refused),
        ("internal_error", WorkspaceControlOutcome.failed),
        ("unavailable", WorkspaceControlOutcome.failed),
    ])
    func closeErrorMapsToOutcome(code: String, outcome: WorkspaceControlOutcome) async {
        let (mac, source) = Self.makeSource()
        mac.workspaces = [Self.workspace("a", order: 0), Self.workspace("b", order: 1)]
        mac.closeResult = .err(code: code, message: "", data: nil)

        #expect(await source.closeWorkspace(workspaceId: "ws-b") == outcome)
    }

    /// A workspace the list does not hold, such as an SSH one, is not found, and the Mac is not asked.
    @Test func unlistedWorkspaceNotFound() async {
        let (mac, source) = Self.makeSource()
        mac.workspaces = [Self.workspace("a", order: 0)]

        #expect(await source.renameWorkspace(workspaceId: "ws-ssh", title: "api") == .notFound)
        #expect(await source.closeWorkspace(workspaceId: "ws-ssh") == .notFound)
        #expect(mac.renames.isEmpty)
        #expect(mac.closes.isEmpty)
    }

    /// The managed policy is read on every call: once it blocks remote control, all three are refused and the Mac
    /// is not asked.
    @Test func blockedPolicyRefusesAll() async {
        let (mac, source) = Self.makeSource()
        mac.workspaces = [Self.workspace("a", order: 0), Self.workspace("b", order: 1)]
        #expect(await source.renameWorkspace(workspaceId: "ws-a", title: "api") == .ok)

        mac.blocked = true

        #expect(await source.createWorkspace().outcome == .refused)
        #expect(await source.renameWorkspace(workspaceId: "ws-a", title: "web") == .refused)
        #expect(await source.closeWorkspace(workspaceId: "ws-b") == .refused)
        #expect(mac.creates == 0)
        #expect(mac.renames.count == 1)
        #expect(mac.closes.isEmpty)
    }

    /// The live create path makes a workspace without selecting it.
    @Test func createDoesNotChangeSelection() async {
        let manager = TabManager()
        let selected = manager.selectedTabId
        let before = manager.tabs.count

        let result = await TerminalController.shared.v2MobileWorkspaceCreate(
            params: [:],
            tabManager: manager,
            idempotencyCache: TerminalController.WorkspaceCreateIdempotencyCache(
                capacity: 16, persistence: InMemoryWorkspaceCreateIdempotencyStore()
            )
        )

        guard case .ok = result else {
            Issue.record("workspace create failed")
            return
        }
        #expect(manager.tabs.count == before + 1)
        #expect(manager.selectedTabId == selected)
    }
}

/// How often a change signal fired.
@MainActor
private final class Counter {
    var count = 0
}

/// The Mac behind a test source: the list it shows, what its control calls answer and record, and its change
/// signal.
@MainActor
private final class FakeMac {
    var workspaces: [LinkWorkspace] = []
    var blocked = false
    var createResult: TerminalController.V2CallResult = .ok(["created_workspace_id": "ws-new"] as [String: Any])
    var renameResult: TerminalController.V2CallResult = .ok([String: Any]())
    var closeResult: TerminalController.V2CallResult = .ok([String: Any]())
    private(set) var creates = 0
    private(set) var renames: [(workspaceId: String, title: String)] = []
    private(set) var closes: [String] = []
    private(set) var attachCount = 0
    private var onChange: (@MainActor () -> Void)?

    var isAttached: Bool { onChange != nil }

    func fireChange() { onChange?() }

    var control: ShellXLinkWorkspaceSource.Control {
        ShellXLinkWorkspaceSource.Control(
            create: { [self] in
                creates += 1
                return createResult
            },
            rename: { [self] workspaceId, title in
                renames.append((workspaceId, title))
                return renameResult
            },
            close: { [self] workspaceId in
                closes.append(workspaceId)
                return closeResult
            },
            isBlocked: { [self] in blocked }
        )
    }

    func signal(_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        attachCount += 1
        self.onChange = onChange
        return { [weak self] in self?.onChange = nil }
    }
}
