import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

@MainActor
final class AppleLinkRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    func testConnectToYourMacRendersEveryStep() throws {
        let title = String(localized: "appleLink.title"), intro = String(localized: "appleLink.intro")
        let steps: [(PairingModel.Step, String)] = [
            (.idle, "apple-link-idle"), (.confirm(machineName: "MacBook Pro"), "apple-link-confirm"),
            (.waitingForMac(machineName: "MacBook Pro"), "apple-link-waiting"), (.failed(.network), "apple-link-failed"),
        ]
        for (step, name) in steps {
            try assertRenders(PairingSheetContent(step: step, camera: .unavailable, title: title, intro: intro), name: name)
        }
    }

    func testInstructionsNoLongerNameTheIPhoneMenuItem() {
        XCTAssertFalse(String(localized: "pairing.instructions").contains("iPhone…"))
    }
}
