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
}
