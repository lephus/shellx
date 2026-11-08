import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import SwiftUI
import XCTest
@testable import ShellX

/// A shell chip's page: the Mac's terminal drawn from fixed screens (a shell, vim, htop, a 320-column Mac window, wide
/// characters, an agent) and the pages shown while it cannot be drawn, each in light and dark (`dev.sh screenshots`
/// writes them out in en and vi).
@MainActor
final class TerminalRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name, settle: 0.2)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    /// `fixture.snapshot`, then each delta, applied to a fresh screen.
    private static func screen(_ fixture: DemoTerminalFixture, deltas: [TerminalGridFrame] = []) -> TerminalScreen {
        var screen = TerminalScreen()
        screen.apply(fixture.snapshot)
        for delta in deltas { screen.apply(delta) }
        return screen
    }

    private func page(_ model: TerminalViewModel, showsKeyBar: Bool = false) -> some View {
        NavigationStack {
            TerminalPane(model: model, terminalId: model.terminalId ?? "t", title: "zsh", showsKeyBar: showsKeyBar)
                .background(Color.appBackground)
                .navigationTitle(Text(verbatim: "shellx-ios"))
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    func testRendersANormalShell() throws {
        let screen = Self.screen(DemoTerminalScreens.shell, deltas: [DemoTerminalScreens.shellTyping])
        XCTAssertEqual(screen.cursor?.x, 29)
        try assertRenders(page(.fixed(terminalId: "t-zsh", screen: screen)), name: "terminal-shell")
    }

    func testRendersVimOnTheAlternateScreen() throws {
        let screen = Self.screen(DemoTerminalScreens.vim)
        XCTAssertTrue(screen.alt)
        XCTAssertEqual(screen.historyRows.count, 0)
        try assertRenders(page(.fixed(terminalId: "t-vim", screen: screen)), name: "terminal-vim")
    }

    func testRendersHtopFittedToWidth() throws {   // Review Focus 5
        let fit = TerminalGeometry.fitScale(cols: 100, cell: TerminalFont.standard.cell, viewportWidth: SnapshotWriter.size.width)
        XCTAssertLessThan(fit, 1)
        XCTAssertGreaterThan(fit, 0.3)
        try assertRenders(page(.fixed(terminalId: "t-htop", screen: Self.screen(DemoTerminalScreens.htop))), name: "terminal-htop")
    }

    func testRendersA320ColumnGridFittedToWidth() throws {   // Review Focus 5, contracts §17
        let ruler = String(repeating: "0123456789", count: 31) + "012345"   // 316 columns
        let wideMac = DemoTerminalFixture(
            cols: 320, rows: 130,
            screen: (0..<130).map { DemoTerminalScreens.runs("{5}" + String(format: "%03d", $0) + "{0} " + ruler) },
            cursor: TerminalCursor(x: 0, y: 129))
        let screen = Self.screen(wideMac)
        XCTAssertEqual(screen.cols, 320)
        XCTAssertEqual(screen.rows, 130)
        let fit = TerminalGeometry.fitScale(cols: 320, cell: TerminalFont.standard.cell, viewportWidth: SnapshotWriter.size.width)
        XCTAssertLessThan(fit, 0.2)
        XCTAssertGreaterThan(fit, 0)
        try assertRenders(page(.fixed(terminalId: "t-mac", screen: screen)), name: "terminal-320-columns")
    }

    func testRendersWideCharacters() throws {
        try assertRenders(page(.fixed(terminalId: "t-notes", screen: Self.screen(DemoTerminalScreens.wide))), name: "terminal-wide")
    }

    func testRendersAnAgentsTerminal() throws {
        try assertRenders(page(.fixed(terminalId: "t-claude", screen: Self.screen(DemoTerminalScreens.agent))), name: "terminal-agent")
    }

    func testRendersTheMacTooOldPlaceholder() throws {
        try assertRenders(page(.fixed(terminalId: "t-zsh", phase: .unsupported)), name: "terminal-needs-update")
    }

    func testRendersWhileItCannotShowTheTerminal() throws {
        let shell = Self.screen(DemoTerminalScreens.shell)
        let states: [(String, TerminalViewModel)] = [
            ("terminal-connecting", .fixed(terminalId: "t", phase: .connecting)),
            ("terminal-offline", .fixed(terminalId: "t", screen: shell, phase: .offline)),
            ("terminal-gone", .fixed(terminalId: "t", phase: .unavailable(.gone))),
            ("terminal-refused", .fixed(terminalId: "t", phase: .unavailable(.refused))),
            ("terminal-failed", .fixed(terminalId: "t", phase: .unavailable(.failed))),
        ]
        var firsts: [Data?] = []
        for (name, model) in states {
            let images = try SnapshotWriter().write(page(model), name: name, settle: 0.2)
            XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), name)
            firsts.append(images.first?.pngData())
        }
        XCTAssertEqual(Set(firsts.compactMap { $0 }).count, states.count, "each state looks different")
    }
}
