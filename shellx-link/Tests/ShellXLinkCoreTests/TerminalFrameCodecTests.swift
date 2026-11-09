import Foundation
import ShellXLinkCore
import XCTest

final class TerminalFrameCodecTests: XCTestCase {
    func testPaletteRoundTrips() throws {
        let palette = TerminalPalette(fg: "#d0d0d0", bg: "#101010", cursor: "#ff8800",
                                      colors: (0..<256).map { String(format: "#%02x%02x%02x", $0, $0, $0) })
        let head = TerminalFrameHead(kind: .snapshot, cols: 80, rows: 24, cursor: TerminalCursor(x: 0, y: 0), palette: palette, history: 3)
        let message = LinkMessage.terminalViewFrame(terminalId: "t-1", frame: TerminalFramePart(revision: 1, head: head))
        XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(message)), message)
    }

    func testEmptyFieldsAreOmitted() throws {
        let part = TerminalFramePart(revision: 2, part: 1, parts: 2, lines: [TerminalLine(y: 0)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try LinkCodec.encode(.terminalViewFrame(terminalId: "t-1", frame: part))) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["v", "t", "terminal_id", "revision", "part", "parts", "lines"])
        XCTAssertEqual((object["lines"] as? [[String: Any]])?.first?.keys.sorted(), ["y"])
        let head = TerminalFrameHead(kind: .delta, cols: 2, rows: 1, cursor: TerminalCursor(x: 0, y: 0))
        let headObject = try XCTUnwrap((JSONSerialization.jsonObject(with: try LinkCodec.encode(
            .terminalViewFrame(terminalId: "t-1", frame: TerminalFramePart(revision: 1, head: head)))) as? [String: Any])?["head"] as? [String: Any])
        XCTAssertEqual(Set(headObject.keys), ["kind", "cols", "rows", "alt", "cursor"])
    }

    func testEncodingChecksTheSameRulesAsDecoding() {
        let bad: [TerminalFramePart] = [
            TerminalFramePart(revision: 0),
            TerminalFramePart(revision: 1, part: 1, parts: 1),
            TerminalFramePart(revision: 1, part: 1, parts: 2, styles: [TerminalStyle(id: 1, fg: 256)]),
            TerminalFramePart(revision: 1, part: 1, parts: 2, styles: [TerminalStyle(id: 1, bgRgb: "336699")]),
            TerminalFramePart(revision: 1, part: 1, parts: 2, lines: [TerminalLine(y: 0, runs: [TerminalRun(text: "x", width: 3)])]),
            TerminalFramePart(revision: 1, part: 1, parts: 2, lines: [TerminalLine(y: 0, runs: [TerminalRun(text: "")])]),
        ]
        for part in bad {
            XCTAssertThrowsError(try LinkCodec.encode(.terminalViewFrame(terminalId: "t-1", frame: part)), "\(part)") {
                XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
            }
        }
    }
}
