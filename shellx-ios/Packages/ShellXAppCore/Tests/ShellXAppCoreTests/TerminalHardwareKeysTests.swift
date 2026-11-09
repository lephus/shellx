import XCTest
@testable import ShellXAppCore

final class TerminalHardwareKeysTests: XCTestCase {
    private func a(_ usage: Int, _ modifiers: TerminalHardwareModifiers = [], composing: Bool = false) -> TerminalHardwareAction {
        TerminalHardwareKeys.action(usage: usage, modifiers: modifiers, composing: composing)
    }

    func testNamedKeysAreSentWithTheirModifiers() {
        XCTAssertEqual(a(0x29), .send(.escape, mods: [])); XCTAssertEqual(a(0x2B), .send(.tab, mods: []))
        XCTAssertEqual(a(0x2B, [.shift]), .send(.tab, mods: [.shift]))
        XCTAssertEqual([a(0x50), a(0x4F), a(0x52), a(0x51)],
                       [.send(.left, mods: []), .send(.right, mods: []), .send(.up, mods: []), .send(.down, mods: [])])
        XCTAssertEqual(a(0x50, [.alternate]), .send(.left, mods: [.alt]))
        XCTAssertEqual(a(0x52, [.control, .shift]), .send(.up, mods: [.ctrl, .shift]))
        XCTAssertEqual([a(0x4A), a(0x4D), a(0x4B), a(0x4E), a(0x4C)],
                       [.send(.home, mods: []), .send(.end, mods: []), .send(.pageUp, mods: []), .send(.pageDown, mods: []),
                        .send(.delete, mods: [])])
    }

    func testCtrlLettersAreKeys() {
        XCTAssertEqual(a(0x06, [.control]), .send(.letter("c"), mods: [.ctrl]))
        XCTAssertEqual(a(0x04, [.control, .shift]), .send(.letter("a"), mods: [.ctrl, .shift]))
        XCTAssertEqual(a(0x1D, [.control]), .send(.letter("z"), mods: [.ctrl]))
    }

    func testTextReturnBackspaceAndSpaceGoThroughTheTextSystem() {
        for (usage, modifiers) in [(0x06, []), (0x06, [.shift]), (0x06, [.alternate]), (0x28, []), (0x2A, []), (0x2C, [])]
            as [(Int, TerminalHardwareModifiers)] {
            XCTAssertEqual(a(usage, modifiers), .system, "\(usage)")
        }
    }

    func testReturnBackspaceAndSpaceWithModifiersAreKeys() {
        XCTAssertEqual(a(0x28, [.control]), .send(.enter, mods: [.ctrl]))
        XCTAssertEqual(a(0x2A, [.alternate]), .send(.backspace, mods: [.alt]))
        XCTAssertEqual(a(0x2C, [.control]), .send(.space, mods: [.ctrl]))
    }

    func testCommandShortcutsAndUnknownKeysGoToTheSystem() {
        XCTAssertEqual(a(0x19, [.command]), .system); XCTAssertEqual(a(0x29, [.command]), .system); XCTAssertEqual(a(0x3A), .system)
    }

    func testComposingHandsEveryKeyToTheSystem() {   // Review Focus 2
        for usage in [0x29, 0x50, 0x2B] { XCTAssertEqual(a(usage, composing: true), .system) }
        XCTAssertEqual(a(0x06, [.control], composing: true), .system)
    }

    func testKeyBarOrderAndKeys() {
        XCTAssertEqual(TerminalBarKey.allCases, [.escape, .tab, .ctrl, .left, .up, .down, .right])
        XCTAssertEqual(TerminalBarKey.allCases.map(\.key), [.escape, .tab, nil, .left, .up, .down, .right])
    }
}
