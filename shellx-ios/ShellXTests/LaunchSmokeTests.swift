import SwiftUI
import XCTest
@testable import ShellX

final class LaunchSmokeTests: XCTestCase {
    func testBundleHasEnglishAndVietnamese() {
        let localizations = Bundle.main.localizations
        XCTAssertTrue(localizations.contains("en"), "\(localizations)")
        XCTAssertTrue(localizations.contains("vi"), "\(localizations)")
    }

    func testDisplayNameIsShellXDev() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "ShellX Dev")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.shellx.dev")
    }

    @MainActor
    func testRootRenders() throws {
        let images = try SnapshotWriter().write(RootView(coordinator: .preview()), name: "root")

        XCTAssertEqual(images.count, 2)
        for image in images {
            XCTAssertEqual(image.size, SnapshotWriter.size)
        }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }
}
