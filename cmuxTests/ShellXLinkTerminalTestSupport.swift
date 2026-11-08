import AppKit
import CMUXMobileCore
import CmuxTerminal
import Foundation
import GhosttyKit
import ShellXLinkCore
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// MARK: - Real Ghostty helpers

extension ScrollbackTestTerminal {
    /// ghostty_surface_set_grid_size, then waits up to 5 s until a capture shows the size.
    func setGrid(columns: Int, rows: Int) async throws {
        let runtime = try #require(surface.surface)
        #expect(ghostty_surface_set_grid_size(runtime, UInt16(columns), UInt16(rows), nil))
        try await linkWaitUntil {
            let frame = self.surface.mobileRenderGridFrame(stateSeq: 0, scrollbackLines: 0, includeTheme: false)?.frame
            return frame?.columns == columns && frame?.rows == rows
        }
    }

    /// Waits up to 5 s until `surface.readText(region: .screen)` contains `text`.
    func waitForScreen(containing text: String) async throws {
        try await linkWaitUntil { self.surface.readText(region: .screen)?.contains(text) == true }
    }

    /// The full, screen-anchored capture of the terminal with `history` rows of scrollback.
    func capture(history: Int) -> MobileTerminalRenderGridFrame? {
        surface.mobileRenderGridFrame(
            stateSeq: 0, full: true, scrollbackLines: history, includeTheme: true, anchor: .screen
        )?.frame
    }

    private func linkWaitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Timed out waiting for the native terminal state")
    }
}
