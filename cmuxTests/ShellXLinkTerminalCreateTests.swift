import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("ShellX Link terminal create", .serialized, .timeLimit(.minutes(1)))
struct ShellXLinkTerminalCreateTests {
    @Test(arguments: [true, false])
    func aNewTabKeepsTheMacsSelection(inTheSelectedWorkspace: Bool) async throws {
        try await withAppContext { manager in
            let selected = try #require(manager.tabs.first)
            let target: Workspace
            if inTheSelectedWorkspace {
                target = selected
            } else {
                target = try #require(manager.addWorkspaceIfActive(
                    select: false, autoWelcomeIfNeeded: false, autoRefreshMetadata: false
                ))
            }
            let pane = try #require(target.bonsplitController.focusedPaneId)
            _ = try #require(target.newTerminalSurface(inPane: pane, focus: true))
            let second = try #require(target.newTerminalSurface(
                inPane: pane, focus: false, preserveBonsplitSelectionWhenUnfocused: true
            ))
            @MainActor func selection() -> [String] {
                [
                    "\(String(describing: target.bonsplitController.selectedTab(inPane: pane)?.id))",
                    "\(String(describing: target.bonsplitController.focusedPaneId))",
                    "\(String(describing: target.focusedPanelId))",
                    "\(String(describing: manager.selectedTabId))",
                ]
            }
            _ = second
            let before = selection()

            let result = TerminalController.shared.v2MobileTerminalCreate(
                params: ["workspace_id": target.id.uuidString], preserveSelection: true
            )

            guard case let .ok(payload) = result, let created = (payload as? [String: Any])?["created_terminal_id"] as? String,
                  let createdID = UUID(uuidString: created) else {
                Issue.record("no terminal created")
                return
            }
            #expect(target.panels[createdID] != nil)
            #expect(selection() == before)
            for _ in 0..<2 { try await Task.sleep(for: .milliseconds(50)) }
            #expect(selection() == before)
        }
    }

    private func withAppContext(_ body: @MainActor (TabManager) async throws -> Void) async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let previousAppDelegate = AppDelegate.shared
            let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
            let appDelegate = AppDelegate()
            let manager = TabManager(autoWelcomeIfNeeded: false)
            AppDelegate.shared = appDelegate
            appDelegate.tabManager = manager
            let windowId = appDelegate.registerMainWindowContextForTesting(tabManager: manager)
            TerminalController.shared.setActiveTabManager(manager)
            defer {
                appDelegate.unregisterMainWindowContextForTesting(windowId: windowId)
                TerminalController.shared.setActiveTabManager(previousManager)
                manager.tabs.forEach { $0.teardownAllPanels() }
                AppDelegate.shared = previousAppDelegate
            }
            try await body(manager)
        }
    }
}
