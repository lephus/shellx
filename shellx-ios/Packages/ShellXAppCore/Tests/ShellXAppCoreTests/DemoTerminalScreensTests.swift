import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import XCTest

/// The demo's terminal content: palette, markup and the fixtures the render tests and the demo Mac show.
final class DemoTerminalScreensTests: XCTestCase {
    func testXterm256() {
        let colors = DemoTerminalScreens.xterm256(base: Array(repeating: "#123456", count: 16))
        XCTAssertEqual(colors.count, 256)
        XCTAssertEqual([colors[16], colors[21], colors[196], colors[231], colors[232], colors[255]],
                       ["#000000", "#0000ff", "#ff0000", "#ffffff", "#080808", "#eeeeee"])
        XCTAssertEqual(DemoTerminalScreens.palette.colors[4], "#60a5fa")
        XCTAssertEqual(DemoTerminalScreens.palette.bg, "#0b0716")
    }

    func testMarkup() {
        XCTAssertEqual(DemoTerminalScreens.runs("{1}$ {0}ls"), [TerminalRun(text: "$ ", style: 1), TerminalRun(text: "ls")])
        XCTAssertEqual(DemoTerminalScreens.runs("a中e\u{301}🇻🇳{z"),
                       [TerminalRun(text: "a"), TerminalRun(text: "中", width: 2), TerminalRun(text: "e\u{301}", width: 1),
                        TerminalRun(text: "🇻🇳", width: 2), TerminalRun(text: "{z")])
    }

    func testEveryFixtureSplitsAndAssemblesIntoItself() throws {
        for (name, fixture) in Self.all {
            let parts = try TerminalFrameSplitter.parts(of: fixture.snapshot, revision: 1, terminalId: "t")
            var assembler = TerminalFrameAssembler()
            XCTAssertEqual(parts.map { assembler.receive($0) }.last?.frame, fixture.snapshot, name)
            var screen = TerminalScreen()
            screen.apply(fixture.snapshot)
            XCTAssertEqual(screen.cols, fixture.cols, name)
            XCTAssertEqual(screen.alt, fixture.alt, name)
            XCTAssertEqual(screen.historyRows.count, fixture.alt ? 0 : fixture.history.count, name)
            XCTAssertLessThanOrEqual(fixture.screen.count, fixture.rows, name)
            if let prompt = fixture.prompt { XCTAssertEqual(fixture.screen[fixture.cursor.y], prompt, name) }
            // No row is wider than its fixture.
            for (index, row) in (fixture.history + fixture.screen + fixture.ticks).enumerated() {
                XCTAssertLessThanOrEqual(Self.columns(row), fixture.cols, "\(name) row \(index)")
            }
        }
    }

    func testTheFixturesHoldWhatTheRenderTestsShow() {
        XCTAssertTrue(DemoTerminalScreens.vim.alt && DemoTerminalScreens.htop.alt && DemoTerminalScreens.agent.alt)
        XCTAssertEqual(DemoTerminalScreens.htop.cols, 100)
        XCTAssertEqual(DemoTerminalScreens.shell.history.count, 30)
        XCTAssertEqual(DemoTerminalScreens.shell.cursor.x, 23)
        let wide = DemoTerminalScreens.wide.screen.flatMap { $0 }
        XCTAssertTrue(wide.contains(TerminalRun(text: "中", width: 2)))
        XCTAssertTrue(wide.contains(TerminalRun(text: "🇻🇳", width: 2)))
        XCTAssertTrue(wide.contains(TerminalRun(text: "e\u{301}", width: 1)))
        XCTAssertEqual(DemoTerminalScreens.devServer.tickInterval, .seconds(3))
        XCTAssertEqual(DemoTerminalScreens.devServer.ticks.count, 4)
        // The rows with an exact width fill their fixture.
        XCTAssertEqual(Self.columns(DemoTerminalScreens.vim.screen[39]), 50)
        XCTAssertEqual(Self.columns(DemoTerminalScreens.htop.screen[7]), 100)
        XCTAssertEqual(Self.columns(DemoTerminalScreens.htop.screen[12]), 100)
        XCTAssertEqual(Self.columns(DemoTerminalScreens.agent.screen[1]), 50)
        XCTAssertEqual(Self.columns(DemoTerminalScreens.agent.screen[37]), 50)
    }

    private static let all: [(String, DemoTerminalFixture)] = [
        ("shell", DemoTerminalScreens.shell), ("devServer", DemoTerminalScreens.devServer), ("wide", DemoTerminalScreens.wide),
        ("vim", DemoTerminalScreens.vim), ("htop", DemoTerminalScreens.htop), ("agent", DemoTerminalScreens.agent),
        ("prompt", DemoTerminalScreens.prompt(cols: 50, rows: 20))]

    /// Columns a row takes: a run with a width is one cell of that width, any other run one column per scalar.
    private static func columns(_ row: [TerminalRun]) -> Int {
        row.reduce(0) { $0 + ($1.width ?? $1.text.unicodeScalars.count) }
    }
}
