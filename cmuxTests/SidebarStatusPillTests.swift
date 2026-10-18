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
}
