import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import XCTest
@testable import ShellX

/// A terminal row cut into segments of one style, each cell at its column, wide and combined cells drawn on their own.
final class TerminalRowLayoutTests: XCTestCase {
    func testCellsOfOneStyleFormOneSegment() {
        let cells = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "ab", style: TerminalCellStyle(fg: 1)),
                                       TerminalStyledRun(x: 2, text: "c")]).cells(cols: 5)
        let segments = TerminalRowLayout.segments(cells, palette: DemoTerminalScreens.palette)
        XCTAssertEqual(segments.map(\.columns), [0..<2, 2..<5])
        XCTAssertEqual(segments[0].narrow.map(\.text), ["a", "b"])
    }

    func testWideAndClusterCellsAreDrawnOnTheirOwn() {
        let cells = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "a"), TerminalStyledRun(x: 1, text: "中", width: 2),
                                       TerminalStyledRun(x: 3, text: "e\u{301}", width: 1)]).cells(cols: 5)
        let segments = TerminalRowLayout.segments(cells, palette: DemoTerminalScreens.palette)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(
            segments[0].clusters,
            [.init(column: 1, width: 2, text: "中"), .init(column: 3, width: 1, text: "e\u{301}")])
        XCTAssertEqual(segments[0].narrow.map(\.column), [0, 4])
    }

    func testTheCellUnderTheCursorIsFound() {
        let row = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "a"), TerminalStyledRun(x: 1, text: "中", width: 2)])
        let layout = TerminalRowLayout(row: row, cols: 5, palette: DemoTerminalScreens.palette, font: .standard)
        XCTAssertEqual(layout.cell(at: 2)?.cell, .init(column: 1, width: 2, text: "中"))
        XCTAssertEqual(layout.cell(at: 0)?.cell.text, "a")
        XCTAssertNil(layout.cell(at: 4))
    }
}
