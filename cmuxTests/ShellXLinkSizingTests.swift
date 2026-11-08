import CmuxTerminalSizing
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("ShellX Link sizing", .serialized, .timeLimit(.minutes(1)))
struct ShellXLinkSizingTests {
    private let phone = "mobile:shellx-link-a"

    @Test func aLinkPhoneOwnsTheGridOnceItOpens() async throws {
        try await withPanel { controller, panelId in
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            let state = controller.terminalSharing.snapshot(for: panelId)?.state
            #expect(state?.policy == .latest && state?.owners == [phone] && state?.cols == 46 && state?.rows == 30)
            #expect(state?.participant(phone)?.counts == true)
            #expect(state?.participant(phone)?.participant.countsOverride == true)
        }
    }

    @Test func macTypingTakesTheGridBack() async throws {
        try await withPanel { controller, panelId in
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            controller.noteLocalTerminalSizingActivity(surfaceID: panelId)
            #expect(controller.terminalSharing.snapshot(for: panelId)?.state.owners == [mac(panelId)])
        }
    }

    @Test func linkInputIsThePhonesActivity() async throws {
        try await withPanel { controller, panelId in
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            controller.noteLocalTerminalSizingActivity(surfaceID: panelId)
            controller.performRemoteParticipantInput(surfaceID: panelId, clientID: "shellx-link-a") {
                controller.noteLocalTerminalSizingActivity(surfaceID: panelId)
            }
            #expect(controller.terminalSharing.snapshot(for: panelId)?.state.owners == [phone])
        }
    }

    @Test func turnsOfTypingHandTheGridBackAndForth() async throws {
        try await withPanel { controller, panelId in
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            for _ in 0..<3 {
                controller.noteLocalTerminalSizingActivity(surfaceID: panelId)
                #expect(controller.terminalSharing.snapshot(for: panelId)?.state.owners == [mac(panelId)])
                controller.performRemoteParticipantInput(surfaceID: panelId, clientID: "shellx-link-a") {
                    controller.noteLocalTerminalSizingActivity(surfaceID: panelId)
                }
                #expect(controller.terminalSharing.snapshot(for: panelId)?.state.owners == [phone])
            }
        }
    }

    @Test func aPhoneResizeIsItsActivityAndItsSize() async throws {
        try await withPanel { controller, panelId in
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            controller.noteLocalTerminalSizingActivity(surfaceID: panelId)
            controller.shellXLinkSizingResize(surfaceID: panelId, clientID: "shellx-link-a", columns: 80, rows: 24)
            let state = controller.terminalSharing.snapshot(for: panelId)?.state
            #expect(state?.owners == [phone] && state?.cols == 80 && state?.rows == 24)
        }
    }

    @Test func closingTheViewGivesTheMacItsSizeAndPolicyBack() async throws {
        try await withPanel { controller, panelId in
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            controller.shellXLinkSizingDetach(surfaceID: panelId, clientID: "shellx-link-a")
            let state = controller.terminalSharing.snapshot(for: panelId)?.state
            #expect(state?.owners == [mac(panelId)] && state?.policy == .fitEveryone && state?.participant(phone) == nil)
            #expect(controller.mobileViewportReportsBySurfaceID[panelId] == nil)
        }
    }

    @Test func aPolicySomeoneChoseIsKept() async throws {
        let largest = TerminalSizingPolicy(mode: .largest)
        try await withPanel { controller, panelId in
            _ = controller.localSizingHost(surfaceID: panelId, create: true)
            _ = controller.localSizingSetPolicy(surfaceID: panelId, policy: largest)
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            controller.shellXLinkSizingDetach(surfaceID: panelId, clientID: "shellx-link-a")
            #expect(controller.terminalSharing.snapshot(for: panelId)?.state.policy == largest)
        }
        try await withPanel { controller, panelId in
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            #expect(controller.terminalSharing.snapshot(for: panelId)?.state.policy == .latest)
            _ = controller.localSizingSetPolicy(surfaceID: panelId, policy: largest)
            controller.shellXLinkSizingDetach(surfaceID: panelId, clientID: "shellx-link-a")
            #expect(controller.terminalSharing.snapshot(for: panelId)?.state.policy == largest)
        }
    }

    @Test func twoLinkPhonesKeepLatestUntilTheLastLeaves() async throws {
        try await withPanel { controller, panelId in
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
            controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-b", columns: 50, rows: 20)
            controller.shellXLinkSizingDetach(surfaceID: panelId, clientID: "shellx-link-a")
            #expect(controller.terminalSharing.snapshot(for: panelId)?.state.policy == .latest)
            controller.shellXLinkSizingDetach(surfaceID: panelId, clientID: "shellx-link-b")
            #expect(controller.terminalSharing.snapshot(for: panelId)?.state.policy == .fitEveryone)
        }
    }

    @Test func otherPhonesKeepTheirRules() async throws {
        try await withPanel { controller, panelId in
            controller.debugSetMobileViewportReportForTesting(surfaceID: panelId, clientID: "iphone-1", columns: 50, rows: 20)
            _ = controller.resolveSharedSizing(
                surfaceID: panelId, reports: controller.mobileViewportReportsBySurfaceID[panelId] ?? [:], reason: "test"
            )
            let state = controller.terminalSharing.snapshot(for: panelId)?.state
            #expect(state?.policy == .fitEveryone && state?.participant("mobile:iphone-1")?.participant.countsOverride == nil)
        }
    }

    private func mac(_ panelId: UUID) -> String { "mac:\(panelId.uuidString.lowercased())" }

    private func withPanel(_ body: @MainActor (TerminalController, UUID) async throws -> Void) async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            let previousAppDelegate = AppDelegate.shared
            let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
            let appDelegate = AppDelegate()
            let manager = TabManager(autoWelcomeIfNeeded: false)
            AppDelegate.shared = appDelegate
            appDelegate.tabManager = manager
            let windowId = appDelegate.registerMainWindowContextForTesting(tabManager: manager)
            TerminalController.shared.setActiveTabManager(manager)
            let controller = TerminalController.shared
            defer {
                controller.debugResetMobileViewportReportsForTesting()
                controller.resetLocalSizingHosts()
                appDelegate.unregisterMainWindowContextForTesting(windowId: windowId)
                TerminalController.shared.setActiveTabManager(previousManager)
                manager.tabs.forEach { $0.teardownAllPanels() }
                AppDelegate.shared = previousAppDelegate
            }
            let workspace = try #require(manager.tabs.first)
            let panelId = try #require(workspace.focusedPanelId)
            try #require(controller.terminalSocketTarget(surfaceID: panelId) != nil)
            try await body(controller, panelId)
        }
    }
}
