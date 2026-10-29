import XCTest

@testable import ShellXAppCore

/// How a permission card lays out its actions (ruling P3-R4): a lasting grant is never the one-tap
/// button.
final class PermissionLayoutTests: XCTestCase {
    func testAllowAndDenyStayInTheRow() {
        let all = PermissionLayout([.allowOnce, .deny, .allowAlways, .allowAllTools])
        XCTAssertEqual(all.buttons, [.deny, .allowOnce])
        XCTAssertEqual(all.menu, [.allowAlways, .allowAllTools])
        XCTAssertEqual(PermissionLayout([.deny]).buttons, [.deny])
        XCTAssertEqual(PermissionLayout([.deny]).menu, [])
    }

    func testLastingGrantIsNeverTheOneTapButton() {
        let noOnce = PermissionLayout([.deny, .allowAlways, .allowAllTools])
        XCTAssertEqual(noOnce.buttons, [.deny], "without Allow (once) the row has Deny only")
        XCTAssertEqual(noOnce.menu, [.allowAlways, .allowAllTools], "lasting grants stay one step away")
        let alwaysOnly = PermissionLayout([.allowAlways])
        XCTAssertEqual(alwaysOnly.buttons, [])
        XCTAssertEqual(alwaysOnly.menu, [.allowAlways])
        let allToolsOnly = PermissionLayout([.allowAllTools, .deny])
        XCTAssertEqual(allToolsOnly.buttons, [.deny])
        XCTAssertEqual(allToolsOnly.menu, [.allowAllTools])
    }

    func testOnlyPermissionActionsAreLaidOut() {
        let layout = PermissionLayout([.answer, .openOnMac, .rejectPlan, .allowOnce])
        XCTAssertEqual(layout.buttons, [.allowOnce])
        XCTAssertEqual(layout.menu, [])
    }
}
