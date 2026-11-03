import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class ShellXAutomationsURLTests: XCTestCase {
    private func link(_ string: String) -> ShellXAutomationsURL? {
        URL(string: string).flatMap(ShellXAutomationsURL.init)
    }

    func testAcceptsTheListLink() {
        XCTAssertEqual(link("shellx://automations"), ShellXAutomationsURL(URL(string: "shellx://automations/")!))
        XCTAssertNotNil(link("shellx://automations"))
        XCTAssertNil(link("shellx://automations")?.focusId)
        XCTAssertNil(link("shellx://automations/")?.focusId)
    }

    func testAcceptsAnAutomationLink() {
        XCTAssertEqual(link("shellx://automations/9F1C-AB")?.focusId, "9F1C-AB")
        XCTAssertEqual(link("shellx://automations/external:pr-digest")?.focusId, "external:pr-digest")
    }

    func testRejectsOtherLinks() {
        XCTAssertNil(link("shellx://auth/callback?code=1"))
        XCTAssertNil(link("shellx://automations/../x"))
        XCTAssertNil(link("shellx://automations/a/b"))
        XCTAssertNil(link("shellx://automations/%2E%2E"))
        XCTAssertNil(link("shellx://automations/abc?x=1"))
        XCTAssertNil(link("shellx://automations/abc#top"))
        XCTAssertNil(link("https://automations/abc"))
        XCTAssertNil(link("shellx-dev-other://automations/abc"))
        XCTAssertNil(link("file:///automations/abc"))
    }
}
