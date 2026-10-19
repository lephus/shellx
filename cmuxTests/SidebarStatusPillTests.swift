import CmuxSidebar
import Foundation
import ShellXBrand
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX W1 Task 10: compact status glyph → sidebar status pill, and the
/// machine header's fixed row height. The pure models are covered by
/// `Packages/Shared/ShellXBrand` tests.
@Suite @MainActor struct SidebarStatusPillTests {
    @Test func pillMapping() {
        #expect(SidebarStatusPill.from(.needsInput) == .waiting)
        #expect(SidebarStatusPill.from(.subagents) == .running)
        #expect(SidebarStatusPill.from(.running) == .running)
        #expect(SidebarStatusPill.from(.pending) == .running)
        #expect(SidebarStatusPill.from(.unseen) == .done)
        #expect(SidebarStatusPill.from(.error) == .error)
        #expect(SidebarStatusPill.from(.idle) == nil)
        #expect(SidebarStatusPill.from(.waiting) == nil)
        #expect(SidebarStatusPill.from(.branch) == nil)
        #expect(SidebarStatusPill.from(.terminal) == nil)
        #expect(SidebarStatusPill.from(.pullRequest(.open)) == nil)
        #expect(SidebarStatusPill.running.color == ShellXPalette.running)
    }

    @Test func headerAndRowHeightsIgnoreTextLength() {
        let short = SidebarWorkspaceTableRowHeightCalculator.height(forMachineHeaderTitle: "Mac")
        let long = SidebarWorkspaceTableRowHeightCalculator.height(
            forMachineHeaderTitle: String(repeating: "Máy tính văn phòng tầng 3 ", count: 6)
        )
        #expect(short == long)
    }

    /// The pill shows with default settings: the snapshot carries the agent
    /// state even when `sidebar.compactAgentStatus` is off (and no glyph is built).
    @Test func snapshotCarriesPillStateWhenCompactStatusIsOff() {
        let workspace = Workspace(
            title: "Project",
            workingDirectory: FileManager.default.currentDirectoryPath,
            portOrdinal: 0
        )
        defer { workspace.teardownAllPanels() }
        workspace.statusEntries["claude_code"] = SidebarStatusEntry(
            key: "claude_code",
            value: "Failed",
            icon: "exclamationmark.triangle.fill",
            color: "#E88A8A"
        )
        // Proves an agent owns the key, so the entry reaches the factory
        // (see SidebarCompactAgentStatusTests.factoryFoldsAgentRowsAndKeepsCustomOnesWhenCompact).
        workspace.agentPIDs["claude_code"] = 4242

        func snapshot(compact: Bool) -> SidebarWorkspaceSnapshotBuilder.Snapshot {
            let defaults = UserDefaults(suiteName: "SidebarStatusPillTests.\(UUID().uuidString)")!
            defaults.set(compact, forKey: "sidebarCompactAgentStatus")
            return SidebarWorkspaceSnapshotFactory(
                workspace: workspace,
                settings: SidebarTabItemSettingsSnapshot(defaults: defaults),
                showsAgentActivity: false
            ).makeSnapshot()
        }

        let off = snapshot(compact: false)
        #expect(off.compactStatusGlyph == nil)
        #expect(off.statusPillGlyphKind == .error)
        #expect(off.statusPillGlyphKind.flatMap { SidebarStatusPill.from($0) } == .error)

        let on = snapshot(compact: true)
        #expect(on.statusPillGlyphKind == on.compactStatusGlyph?.kind)
    }

    /// The row applies unread to the pill state the way the compact glyph
    /// does, so a settled row with unread notifications shows "done".
    @Test func unreadTurnsASettledRowDone() {
        let settled = SidebarCompactStatusGlyph(kind: .terminal, tooltip: "")
        #expect(SidebarStatusPill.from(settled.applyingUnread(1, latestNotificationText: nil).kind) == .done)
        #expect(SidebarStatusPill.from(settled.applyingUnread(0, latestNotificationText: nil).kind) == nil)
        let waiting = SidebarCompactStatusGlyph(kind: .needsInput, tooltip: "")
        #expect(SidebarStatusPill.from(waiting.applyingUnread(3, latestNotificationText: nil).kind) == .waiting)
    }
}
