import Foundation
import Testing
@testable import ShellXBrand

@Suite struct SidebarStatusPillModelTests {
    @Test func pillColorsFollowThePalette() {
        #expect(SidebarStatusPill.waiting.color == ShellXPalette.primary)
        #expect(SidebarStatusPill.running.color == ShellXPalette.running)
        #expect(SidebarStatusPill.done.color == ShellXPalette.done)
        #expect(SidebarStatusPill.error.color == ShellXPalette.error)
    }

    @Test func waitingTextUsesPrimaryText() {
        #expect(SidebarStatusPill.waiting.textColor == ShellXPalette.primaryText)
        #expect(SidebarStatusPill.running.textColor == ShellXPalette.running)
        #expect(SidebarStatusPill.done.textColor == ShellXPalette.done)
        #expect(SidebarStatusPill.error.textColor == ShellXPalette.error)
    }

    @Test func pillFillIsTheColorAtTwelvePercent() {
        #expect(SidebarStatusPill.fillAlpha == 0.12)
    }

    @Test func pillTitlesFallBackToEnglish() {
        // The test bundle carries no catalog, so the English defaults come back.
        #expect(SidebarStatusPill.waiting.title == "waiting")
        #expect(SidebarStatusPill.running.title == "running")
        #expect(SidebarStatusPill.done.title == "done")
        #expect(SidebarStatusPill.error.title == "error")
    }

    @Test func headerHeightIgnoresTextLength() {
        let short = SidebarMachineHeaderLayout.height(forTitle: "Mac")
        let long = SidebarMachineHeaderLayout.height(
            forTitle: String(repeating: "Máy tính văn phòng tầng 3 ", count: 6)
        )
        #expect(short == long)
        #expect(short == SidebarMachineHeaderLayout.height)
        #expect(short > 0)
    }
}
