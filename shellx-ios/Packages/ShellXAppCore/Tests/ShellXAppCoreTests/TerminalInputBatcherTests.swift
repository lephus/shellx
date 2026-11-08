import XCTest
@testable import ShellXAppCore

final class TerminalInputBatcherTests: XCTestCase {
    func testSmallInputIsOneMessage() {
        XCTAssertEqual(TerminalInputBatcher.messages([.text("ls"), .key(.enter, mods: [])]), [[.text("ls"), .key(.enter, mods: [])]])
    }

    func testEveryMessagePassesTheProtocolCheck() throws {
        let units: [TerminalInputUnit] = Array(repeating: .key(.tab, mods: []), count: 100)
            + [.text(String(repeating: "é", count: 10_000))] + TerminalInputBatcher.pasteUnits(String(repeating: "a", count: 40_000))
        let messages = TerminalInputBatcher.messages(units)
        for message in messages { XCTAssertNoThrow(try TerminalInputCheck.check(message)) }
        let typed = messages.flatMap { $0 }.compactMap { unit -> String? in
            if case let .text(t) = unit { return t }; return nil
        }.joined()
        XCTAssertEqual(typed, String(repeating: "é", count: 10_000))
    }

    func testTypedTextSplitsAt4096UTF8Bytes() {
        let messages = TerminalInputBatcher.messages([.text(String(repeating: "é", count: 3000))])
        XCTAssertEqual(messages, [[.text(String(repeating: "é", count: 2048))], [.text(String(repeating: "é", count: 952))]])
    }

    func testNoMessageHoldsMoreThan64Units() {
        XCTAssertEqual(TerminalInputBatcher.messages(Array(repeating: .key(.tab, mods: []), count: 100)).map(\.count), [64, 36])
    }

    func testAClusterIsNeverCut() {
        let family = "👨‍👩‍👧‍👦"                                        // 25 UTF-8 bytes, one Character
        let text = String(repeating: family, count: 200)
        let pieces = TerminalInputBatcher.messages([.text(text)]).flatMap { $0 }.compactMap { unit -> String? in
            if case let .text(t) = unit { return t }; return nil
        }
        XCTAssertEqual(pieces.joined(), text)
        XCTAssertTrue(pieces.allSatisfy { $0.utf8.count == $0.count * 25 }, "every piece is whole families")
    }

    func testPasteLimitIs256KiB() {
        XCTAssertEqual(TerminalInputBatcher.maxPasteBytes, 262_144)
        XCTAssertTrue(TerminalInputBatcher.pasteFits(String(repeating: "a", count: 262_144)))
        XCTAssertFalse(TerminalInputBatcher.pasteFits(String(repeating: "a", count: 262_145)))
        XCTAssertTrue(TerminalInputBatcher.pasteFits(String(repeating: "a", count: 262_144) + "\u{1b}"))   // dropped controls do not count
    }

    func testPasteSplitsAt16384BytesAndDropsWhatTheProtocolRefuses() {
        XCTAssertEqual(TerminalInputBatcher.pasteUnits("a\u{1b}[201~b\r\n\tc\u{7f}"), [.paste("a[201~b\r\n\tc")])
        XCTAssertEqual(TerminalInputBatcher.pasteUnits(""), []); XCTAssertEqual(TerminalInputBatcher.pasteUnits("\u{1b}"), [])
        let messages = TerminalInputBatcher.messages(TerminalInputBatcher.pasteUnits(String(repeating: "a", count: 20_000)))
        XCTAssertEqual(messages, [[.paste(String(repeating: "a", count: 16_384))], [.paste(String(repeating: "a", count: 3_616))]])
    }

    func testScrollUnitsHoldAtMost100Lines() {
        XCTAssertEqual(TerminalInputBatcher.scrollUnits(250), [.scroll(lines: 100), .scroll(lines: 100), .scroll(lines: 50)])
        XCTAssertEqual(TerminalInputBatcher.scrollUnits(-3), [.scroll(lines: -3)])
        XCTAssertEqual(TerminalInputBatcher.scrollUnits(0), [])
    }
}
