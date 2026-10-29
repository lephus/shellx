import XCTest

@testable import ShellXAppCore

/// The sheets open over the signed-in screens, counted so a pairing link can wait for them
/// (final review, Minor 8).
@MainActor
final class SheetPresenceTests: XCTestCase {
    func testCountsEachOpenSheet() {
        let sheets = SheetPresence()
        XCTAssertFalse(sheets.isAnyOpen)

        sheets.opened()
        XCTAssertTrue(sheets.isAnyOpen)
        // A sheet's content can appear again before the old one went (a new item replaces it).
        sheets.opened()
        sheets.closed()
        XCTAssertTrue(sheets.isAnyOpen, "one sheet is still up")
        sheets.closed()
        XCTAssertFalse(sheets.isAnyOpen)

        // An extra close (a disappear without an appear) never goes below none.
        sheets.closed()
        sheets.opened()
        XCTAssertTrue(sheets.isAnyOpen)
    }
}
