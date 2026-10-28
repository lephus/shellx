import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// A rename the Mac would refuse for its size (more than `ShellXLink.maxWorkspaceTitleBytes` UTF-8 bytes) is
/// answered `bad_request`, which the phone can only show as "try again later": what the phone sends must fit.
final class WorkspaceTitleTests: XCTestCase {
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    func testADecomposedVietnameseNameIsSentComposed() {
        // `==` on String ignores the form: compare the bytes that go on the wire.
        let composed = "Tiếng Việt".precomposedStringWithCanonicalMapping
        let decomposed = composed.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(bytes(decomposed), bytes(composed))

        XCTAssertEqual(bytes(WorkspaceTitle.cleaned(" \(decomposed) ")), bytes(composed))
    }

    func testALongDecomposedNameFitsOnceComposed() {
        // "ệ" is 5 bytes decomposed, 3 composed: 128 of them are 640 bytes, or 384.
        let composed = String(repeating: "ệ".precomposedStringWithCanonicalMapping, count: WorkspaceTitle.maxCharacters)
        let decomposed = composed.decomposedStringWithCanonicalMapping
        XCTAssertGreaterThan(decomposed.utf8.count, ShellXLink.maxWorkspaceTitleBytes)

        let sent = WorkspaceTitle.cleaned(decomposed)

        XCTAssertEqual(bytes(sent), bytes(composed), "every character kept, composed")
        XCTAssertLessThanOrEqual(sent.utf8.count, ShellXLink.maxWorkspaceTitleBytes)
    }

    func testAnEmojiNameIsCutToTheByteLimitOnACharacterBoundary() {
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.utf8.count, 25)
        let title = String(repeating: family, count: WorkspaceTitle.maxCharacters)

        let sent = WorkspaceTitle.cleaned(title)

        XCTAssertLessThanOrEqual(sent.utf8.count, ShellXLink.maxWorkspaceTitleBytes)
        XCTAssertEqual(sent, String(repeating: family, count: ShellXLink.maxWorkspaceTitleBytes / 25), "whole emoji only")
    }

    func testTheCharacterCapStillHoldsAndTheCutLeavesNoSpaceAtTheEnd() {
        XCTAssertEqual(WorkspaceTitle.cleaned(String(repeating: "a", count: 200)), String(repeating: "a", count: 128))
        let spaceAtTheCut = String(repeating: "x", count: 127) + " " + String(repeating: "y", count: 10)
        XCTAssertEqual(WorkspaceTitle.cleaned(spaceAtTheCut), String(repeating: "x", count: 127))
    }

    func testANameNeedsSomethingBesidesSpaces() {
        XCTAssertFalse(WorkspaceTitle.canSave(""))
        XCTAssertFalse(WorkspaceTitle.canSave("  \n\t "))
        XCTAssertTrue(WorkspaceTitle.canSave(" relay "))
        XCTAssertEqual(WorkspaceTitle.cleaned("  relay \n"), "relay")
    }
}
