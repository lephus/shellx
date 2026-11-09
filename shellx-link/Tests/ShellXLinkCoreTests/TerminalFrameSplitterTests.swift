import Foundation
@testable import ShellXLinkCore
import XCTest

final class TerminalFrameSplitterTests: XCTestCase {
    func testSmallFrameIsOnePart() throws {
        let frame = TerminalGridFrame(head: TerminalFrameHead(kind: .delta, cols: 10, rows: 2, cursor: TerminalCursor(x: 0, y: 0)),
                                      lines: [TerminalLine(y: 0, runs: [TerminalRun(text: "hi")])])
        XCTAssertEqual(try TerminalFrameSplitter.parts(of: frame, revision: 3, terminalId: "t-1"),
                       [TerminalFramePart(revision: 3, part: 0, parts: 1, head: frame.head, styles: [], lines: frame.lines)])
    }

    func testBigSnapshotSplitsWithinTheFrameLimit() throws {
        // 300 x 120 cells, each its own style (36 000 styles), plus 240 history rows of text.
        let frame = Self.bigSnapshot()
        let parts = try TerminalFrameSplitter.parts(of: frame, revision: 1, terminalId: "t-1")
        XCTAssertGreaterThan(parts.count, 1)
        for (index, part) in parts.enumerated() {
            XCTAssertEqual(part.part, index)
            XCTAssertEqual(part.parts, parts.count)
            XCTAssertEqual(part.revision, 1)
            XCTAssertEqual(part.head != nil, index == 0)
            XCTAssertLessThanOrEqual(try LinkCodec.encode(.terminalViewFrame(terminalId: "t-1", frame: part)).count, LinkCodec.maxFrameBytes)
        }
        var assembler = TerminalFrameAssembler()
        let results = parts.map { assembler.receive($0) }
        XCTAssertEqual(results.last?.frame, frame)
        XCTAssertFalse(results.contains { $0.resync })
    }

    func testOversizedLineSplitsIntoLinesWithTheSameY() throws {
        let runs = (0..<1000).map { _ in TerminalRun(text: "e" + String(repeating: "\u{0301}", count: 15), width: 1) } // no x
        let frame = TerminalGridFrame(head: TerminalFrameHead(kind: .snapshot, cols: 1000, rows: 1, cursor: TerminalCursor(x: 0, y: 0),
                                                              palette: Self.palette), lines: [TerminalLine(y: 0, runs: runs)])
        let parts = try TerminalFrameSplitter.parts(of: frame, revision: 1, terminalId: "t-1", maxBytes: 4096, maxParts: 256)
        let lines = parts.flatMap(\.lines)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.allSatisfy { $0.y == 0 })
        XCTAssertEqual(lines.flatMap(\.runs).count, 1000)
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.runs.first?.x != nil })
        var assembler = TerminalFrameAssembler()
        let joined = try XCTUnwrap(parts.map { assembler.receive($0) }.last?.frame)
        var split = TerminalScreen()
        split.apply(joined)
        var whole = TerminalScreen()
        whole.apply(frame)
        XCTAssertEqual(split.screenRows[0].cells(cols: 1000), whole.screenRows[0].cells(cols: 1000))
    }

    func testTooManyPartsThrows() {
        let lines = (0..<100).map { TerminalLine(y: $0, runs: [TerminalRun(text: String(repeating: "x", count: 500))]) }
        let frame = TerminalGridFrame(head: TerminalFrameHead(kind: .delta, cols: 500, rows: 100, cursor: TerminalCursor(x: 0, y: 0)), lines: lines)
        XCTAssertThrowsError(try TerminalFrameSplitter.parts(of: frame, revision: 1, terminalId: "t-1", maxBytes: 1024, maxParts: 2)) {
            XCTAssertEqual($0 as? LinkCodecError, .frameTooLarge)
        }
    }

    func testStylesComeBeforeLines() throws {
        // 300 styles and 300 lines with a small limit: once a part has lines, no later part has styles
        let parts = try TerminalFrameSplitter.parts(of: Self.manyStylesAndLines(), revision: 1, terminalId: "t-1", maxBytes: 2048, maxParts: 256)
        let firstWithLines = try XCTUnwrap(parts.firstIndex { !$0.lines.isEmpty })
        XCTAssertTrue(parts[(firstWithLines + 1)...].allSatisfy { $0.styles.isEmpty })
    }

    // MARK: - Helpers

    private static let palette = TerminalPalette(
        fg: "#d0d0d0", bg: "#101010", cursor: nil, colors: (0..<256).map { String(format: "#%02x%02x%02x", $0, $0, $0) })

    private static func bigSnapshot() -> TerminalGridFrame {
        let cols = 300, rows = 120
        var styles: [TerminalStyle] = []
        var lines: [TerminalLine] = []
        for y in 0..<rows {
            var runs: [TerminalRun] = []
            for x in 0..<cols {
                let id = y * cols + x + 1
                styles.append(TerminalStyle(id: id, fg: id % 256, bgRgb: String(format: "#%06x", id & 0xFFFFFF), attrs: [.bold]))
                runs.append(TerminalRun(text: "x", style: id))
            }
            lines.append(TerminalLine(y: y, runs: runs))
        }
        for h in 1...240 { lines.append(TerminalLine(y: -h, runs: [TerminalRun(text: "history row \(h)")])) }
        let head = TerminalFrameHead(
            kind: .snapshot, cols: cols, rows: rows, cursor: TerminalCursor(x: 0, y: 0), palette: palette, history: 240)
        return TerminalGridFrame(head: head, styles: styles, lines: lines)
    }

    private static func manyStylesAndLines() -> TerminalGridFrame {
        let styles = (1...300).map { TerminalStyle(id: $0, fg: $0 % 256, attrs: [.italic]) }
        let lines = (0..<300).map { TerminalLine(y: $0, runs: [TerminalRun(text: "line \($0)", style: $0 + 1)]) }
        return TerminalGridFrame(head: TerminalFrameHead(kind: .delta, cols: 80, rows: 300, cursor: TerminalCursor(x: 0, y: 0)),
                                 styles: styles, lines: lines)
    }
}
