import XCTest
@testable import ShellXAppCore

final class TerminalTypingTests: XCTestCase {
    func testCommittedTextIsSentAndMarkedTextIsNot() {
        var typing = TerminalTyping()
        XCTAssertEqual(typing.setMarked("v"), []); XCTAssertEqual(typing.setMarked("vi"), []); XCTAssertEqual(typing.setMarked("việ"), [])
        XCTAssertEqual(typing.markedText, "việ")
        XCTAssertEqual(typing.insert("việt"), [.text("việt")])
        XCTAssertEqual(typing.markedText, "")
    }

    func testUnmarkCommitsWhatWasComposed() {
        var typing = TerminalTyping()
        _ = typing.setMarked("Tiế")
        XCTAssertEqual(typing.unmark(), [.text("Tiế")]); XCTAssertEqual(typing.unmark(), [])
    }

    func testBackspaceWhileComposingStaysOnThePhone() {
        var typing = TerminalTyping()
        _ = typing.setMarked("việ")
        XCTAssertEqual(typing.deleteBackward(), []); XCTAssertEqual(typing.markedText, "vi")
        _ = typing.setMarked("")
        XCTAssertEqual(typing.deleteBackward(), [.key(.backspace, mods: [])])
    }

    func testLineBreaksAndTabsAreKeys() {
        var typing = TerminalTyping()
        XCTAssertEqual(typing.insert("ls\n"), [.text("ls"), .key(.enter, mods: [])])
        XCTAssertEqual(typing.insert("a\r\nb\tc"), [.text("a"), .key(.enter, mods: []), .text("b"), .key(.tab, mods: []), .text("c")])
        XCTAssertEqual(typing.insert("\r"), [.key(.enter, mods: [])])
    }

    func testOtherControlCharactersAreDropped() {
        var typing = TerminalTyping()
        XCTAssertEqual(typing.insert("a\u{1b}[31mb\u{7f}\u{85}"), [.text("a[31mb")])
        XCTAssertEqual(typing.insert("\u{1b}"), [])
    }

    func testCtrlLatchesForTheNextKeyOnly() {
        var typing = TerminalTyping()
        typing.toggleCtrl(); XCTAssertTrue(typing.ctrlLatched)
        XCTAssertEqual(typing.insert("c"), [.key(.letter("c"), mods: [.ctrl])]); XCTAssertFalse(typing.ctrlLatched)
        XCTAssertEqual(typing.insert("c"), [.text("c")])
        typing.toggleCtrl(); typing.toggleCtrl(); XCTAssertFalse(typing.ctrlLatched)
    }

    func testCtrlWithAnUppercaseLetterSpaceOrReturn() {
        var typing = TerminalTyping()
        typing.toggleCtrl(); XCTAssertEqual(typing.insert("C"), [.key(.letter("c"), mods: [.ctrl])])
        typing.toggleCtrl(); XCTAssertEqual(typing.insert(" "), [.key(.space, mods: [.ctrl])])
        typing.toggleCtrl(); XCTAssertEqual(typing.insert("\n"), [.key(.enter, mods: [.ctrl])])
    }

    func testCtrlWithAnyOtherCharacterTypesItPlain() {
        var typing = TerminalTyping()
        typing.toggleCtrl(); XCTAssertEqual(typing.insert("1x"), [.text("1x")]); XCTAssertFalse(typing.ctrlLatched)
        typing.toggleCtrl(); XCTAssertEqual(typing.insert("đ"), [.text("đ")])
    }

    func testCtrlAppliesToTheKeyBarAndHardwareKeys() {
        var typing = TerminalTyping()
        typing.toggleCtrl(); XCTAssertEqual(typing.key(.left), [.key(.left, mods: [.ctrl])])
        XCTAssertEqual(typing.key(.left), [.key(.left, mods: [])])
        typing.toggleCtrl(); XCTAssertEqual(typing.key(.letter("c"), mods: [.ctrl]), [.key(.letter("c"), mods: [.ctrl])])
    }

    func testCtrlLatchedTakesTheFirstLetterOfANewComposition() {
        var typing = TerminalTyping()
        typing.toggleCtrl()
        XCTAssertEqual(typing.setMarked("c"), [.key(.letter("c"), mods: [.ctrl])])
        XCTAssertEqual(typing.markedText, ""); XCTAssertFalse(typing.ctrlLatched)
    }

    func testCtrlTappedWhileComposingWaitsForTheNextKey() {   // Review Focus 2
        var typing = TerminalTyping()
        _ = typing.setMarked("việ"); typing.toggleCtrl()
        XCTAssertEqual(typing.setMarked("việt"), []); XCTAssertEqual(typing.markedText, "việt")
        XCTAssertEqual(typing.unmark(), [.text("việt")]); XCTAssertTrue(typing.ctrlLatched)
        XCTAssertEqual(typing.key(.letter("c")), [.key(.letter("c"), mods: [.ctrl])])
        _ = typing.setMarked("viê"); typing.toggleCtrl()
        XCTAssertEqual(typing.insert("việt"), [.text("việt")], "committing a word is never a ctrl chord")
        XCTAssertTrue(typing.ctrlLatched)
    }

    func testAKeyWhileComposingCommitsTheWordFirst() {   // Review Focus 2
        var typing = TerminalTyping()
        _ = typing.setMarked("việ")
        XCTAssertEqual(typing.key(.left), [.text("việ"), .key(.left, mods: [])])
        XCTAssertEqual(typing.markedText, "")
    }
}
