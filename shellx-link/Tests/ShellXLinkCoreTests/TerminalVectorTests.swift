import Foundation
import ShellXLinkCore
import XCTest

/// The vectors of PROTOCOL.md section 11 (`spec/vectors/terminal.json`).
final class TerminalVectorTests: XCTestCase {
    static func vectors() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spec/vectors/terminal.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testLimitsMatchTheVectors() throws {
        let l = try XCTUnwrap(try Self.vectors()["limits"] as? [String: Any])
        XCTAssertEqual(l["columns"] as? [Int], [ShellXLink.terminalColumns.lowerBound, ShellXLink.terminalColumns.upperBound])
        XCTAssertEqual(l["rows"] as? [Int], [ShellXLink.terminalRows.lowerBound, ShellXLink.terminalRows.upperBound])
        XCTAssertEqual(l["max_grid_size"] as? Int, ShellXLink.terminalMaxGridSize)
        XCTAssertEqual(l["max_frame_parts"] as? Int, ShellXLink.terminalMaxFrameParts)
        XCTAssertEqual(l["max_cell_text_bytes"] as? Int, ShellXLink.terminalMaxCellTextBytes)
        XCTAssertEqual(l["snapshot_history_rows"] as? Int, ShellXLink.terminalSnapshotHistoryRows)
        XCTAssertEqual(l["history_row_budget"] as? Int, ShellXLink.terminalHistoryRowBudget)
        XCTAssertEqual(l["history_fill_max_bytes"] as? Int, ShellXLink.terminalHistoryFillMaxBytes)
        XCTAssertEqual(l["max_delta_history_rows"] as? Int, ShellXLink.terminalMaxDeltaHistoryRows)
        XCTAssertEqual(l["max_input_units"] as? Int, ShellXLink.terminalMaxInputUnits)
        XCTAssertEqual(l["max_text_bytes"] as? Int, ShellXLink.terminalMaxTextBytes)
        XCTAssertEqual(l["max_paste_bytes"] as? Int, ShellXLink.terminalMaxPasteBytes)
        XCTAssertEqual(l["max_scroll_lines"] as? Int, ShellXLink.terminalMaxScrollLines)
        XCTAssertEqual(l["max_queued_inputs"] as? Int, ShellXLink.terminalMaxQueuedInputs)
    }

    func testKeyAndModifierNames() throws {
        let file = try Self.vectors()
        let keys = try XCTUnwrap(file["keys"] as? [String])
        XCTAssertEqual(keys.count, 40)
        XCTAssertEqual(TerminalKey.allKnown.map(\.wire), keys)
        for key in keys { XCTAssertEqual(TerminalKey(wire: key).wire, key) }
        XCTAssertEqual(TerminalKey(wire: "page_up"), .pageUp)
        XCTAssertEqual(TerminalKey(wire: "c"), .letter("c"))
        XCTAssertEqual(TerminalKey(wire: "C"), .other("C"))
        XCTAssertEqual(TerminalKey(wire: "f13"), .other("f13"))
        XCTAssertEqual([TerminalModifier.ctrl, .alt, .shift].map(\.wire), try XCTUnwrap(file["modifiers"] as? [String]))
        XCTAssertEqual(TerminalModifier(wire: "cmd"), .other("cmd"))
    }

    func testInputChecks() throws {
        let checks = try XCTUnwrap(try Self.vectors()["input_checks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 27)
        for check in checks {
            let name = check["name"] as? String ?? "?"
            let frame: [String: Any] = ["v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": try XCTUnwrap(check["units"])]
            guard case let .terminalViewInput(_, units) = try LinkCodec.decode(try JSONSerialization.data(withJSONObject: frame)) else {
                return XCTFail("\(name) did not decode as terminal.view.input")
            }
            let passed = (try? TerminalInputCheck.check(units)) != nil
            XCTAssertEqual(passed, try XCTUnwrap(check["ok"] as? Bool), name)
        }
    }

    func testInputErrorNeverQuotesTheText() {
        XCTAssertThrowsError(try TerminalInputCheck.check([.text("hunter2\n")])) { error in
            XCTAssertFalse((error as? TerminalInputError)?.reason.contains("hunter2") ?? true)
        }
    }

    func testFeatureNames() {
        XCTAssertEqual(ShellXLink.terminalViewFeature, "terminal_view")
        XCTAssertEqual(ShellXLink.terminalCreateFeature, "terminal_create")
    }

    func testScreens() throws {
        let file = try Self.vectors()
        let palette = try XCTUnwrap(file["palette"])
        let screens = try XCTUnwrap(file["screens"] as? [[String: Any]])
        XCTAssertEqual(screens.count, 17)
        for entry in screens {
            let name = entry["name"] as? String ?? "?"
            var assembler = TerminalFrameAssembler()
            var screen = TerminalScreen(maxHistoryRows: entry["max_history_rows"] as? Int ?? TerminalScreen.defaultMaxHistoryRows)
            var resyncs = 0
            for var frame in try XCTUnwrap(entry["frames"] as? [[String: Any]]) {
                if var head = frame["head"] as? [String: Any], head["palette"] as? String == "@palette" {
                    head["palette"] = palette
                    frame["head"] = head
                }
                let message = try LinkCodec.decode(try JSONSerialization.data(withJSONObject: frame))
                guard case let .terminalViewFrame("t-1", part) = message else {
                    XCTFail("\(name): not a frame"); continue
                }
                let result = assembler.receive(part)
                if let applied = result.frame { screen.apply(applied) }
                if result.resync { resyncs += 1 }
            }
            let expect = try XCTUnwrap(entry["expect"] as? [String: Any], name)
            XCTAssertEqual(assembler.revision, expect["revision"] as? Int, name)
            XCTAssertEqual(resyncs, expect["resyncs"] as? Int, name)
            XCTAssertEqual(screen.cols, expect["cols"] as? Int, name)
            XCTAssertEqual(screen.rows, expect["rows"] as? Int, name)
            XCTAssertEqual(screen.alt, expect["alt"] as? Bool, name)
            if let cursor = expect["cursor"] as? [String: Any] {
                XCTAssertEqual(screen.cursor, TerminalCursor(
                    x: try XCTUnwrap(cursor["x"] as? Int), y: try XCTUnwrap(cursor["y"] as? Int),
                    shape: TerminalCursorShape(wire: try XCTUnwrap(cursor["shape"] as? String)),
                    visible: try XCTUnwrap(cursor["visible"] as? Bool), blink: try XCTUnwrap(cursor["blink"] as? Bool)), name)
            }
            XCTAssertEqual(screen.screenText(), expect["screen"] as? [String], name)
            XCTAssertEqual(screen.historyText(), expect["history"] as? [String], name)
            for cell in expect["cells"] as? [[String: Any]] ?? [] {
                let x = try XCTUnwrap(cell["x"] as? Int), y = try XCTUnwrap(cell["y"] as? Int)
                let expected: TerminalCell
                switch cell["kind"] as? String {
                case "blank": expected = .blank
                case "continuation": expected = .continuation
                default:
                    let style = cell["style"] as? [String: Any]
                    expected = .glyph(
                        text: try XCTUnwrap(cell["t"] as? String), width: try XCTUnwrap(cell["w"] as? Int),
                        style: TerminalCellStyle(
                            fg: style?["fg"] as? Int, fgRgb: style?["fg_rgb"] as? String, bg: style?["bg"] as? Int,
                            bgRgb: style?["bg_rgb"] as? String,
                            attrs: (style?["attrs"] as? [String] ?? []).map(TerminalAttribute.init(wire:))))
                }
                XCTAssertEqual(screen.cell(x: x, y: y), expected, "\(name) (\(x),\(y))")
            }
        }
    }
}
