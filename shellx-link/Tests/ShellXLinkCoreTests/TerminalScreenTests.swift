import ShellXLinkCore
import XCTest

final class TerminalScreenTests: XCTestCase {
    func testRowTextSkipsTheSecondColumnOfAWideCell() {
        let row = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "a"), TerminalStyledRun(x: 1, text: "中", width: 2)])
        XCTAssertEqual(row.text(cols: 5), "a中")
        XCTAssertEqual(row.cells(cols: 5), [.glyph(text: "a", width: 1, style: .default),
                                           .glyph(text: "中", width: 2, style: .default), .continuation, .blank, .blank])
    }

    func testLaterRunOverwritesCellByCell() {
        let row = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "abc"), TerminalStyledRun(x: 1, text: "Z")])
        XCTAssertEqual(row.text(cols: 3), "aZc")
    }

    func testScreenStartsEmpty() {
        let screen = TerminalScreen()
        XCTAssertEqual(screen.cols, 0)
        XCTAssertNil(screen.cursor)
        XCTAssertEqual(screen.screenText(), [])
        XCTAssertEqual(screen.historyText(), [])
    }

    func testOverwritingHalfAWideCellLeavesNoHalfGlyph() {
        let row = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "中", width: 2), TerminalStyledRun(x: 1, text: "x")])
        XCTAssertEqual(row.cells(cols: 3), [.blank, .glyph(text: "x", width: 1, style: .default), .blank])
    }
}
