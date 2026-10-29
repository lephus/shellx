import UIKit
import XCTest
@testable import ShellX

/// Settings › Appearance: what is stored, and that the choice lands on the app's windows.
@MainActor
final class AppearanceTests: XCTestCase {
    func testStoredChoiceDefaultsToMatchIPhone() {
        XCTAssertEqual(AppAppearance(stored: nil), .system)
        XCTAssertEqual(AppAppearance(stored: "sepia"), .system, "an unknown value is not a crash")
        for appearance in AppAppearance.allCases {
            XCTAssertEqual(AppAppearance(stored: appearance.rawValue), appearance)
        }
    }

    func testEachChoiceHasItsStyle() {
        XCTAssertEqual(AppAppearance.system.style, .unspecified)
        XCTAssertEqual(AppAppearance.light.style, .light)
        XCTAssertEqual(AppAppearance.dark.style, .dark)
    }

    func testApplySetsEveryWindowAndMatchIPhoneUndoesIt() throws {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        try XCTSkipIf(windows.isEmpty, "the test host has no window")
        addTeardownBlock { @MainActor in AppAppearance.system.apply() }

        AppAppearance.dark.apply()
        XCTAssertTrue(windows.allSatisfy { $0.overrideUserInterfaceStyle == .dark })
        AppAppearance.light.apply()
        XCTAssertTrue(windows.allSatisfy { $0.overrideUserInterfaceStyle == .light })
        AppAppearance.system.apply()
        XCTAssertTrue(windows.allSatisfy { $0.overrideUserInterfaceStyle == .unspecified })
    }
}
