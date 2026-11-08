import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

@MainActor
final class DeleteAccountRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    func testDeleteSheetRendersEveryStep() throws {
        let steps: [(DeleteAccountSheet.Step, String)] = [
            (.confirm, "delete-account-confirm"), (.switchFirst, "delete-account-switch-first"), (.working, "delete-account-working"),
            (.failed(SignInErrorText.message(for: .reauthRequired) ?? ""), "delete-account-failed"),
        ]
        for (step, name) in steps { try assertRenders(DeleteAccountSheet(step: step), name: name) }
    }
}
