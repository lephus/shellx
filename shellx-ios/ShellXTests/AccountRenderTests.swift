import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

@MainActor
final class AccountRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    func testSignInRenders() throws {
        try assertRenders(SignInView(coordinator: .preview(), expired: false), name: "signin")
    }

    func testSignInWithErrorRenders() throws {
        try assertRenders(
            SignInView(coordinator: .preview(), expired: false, initialError: .invalidCredentials),
            name: "signin-error")
    }

    func testSignInExpiredRenders() throws {
        try assertRenders(SignInView(coordinator: .preview(), expired: true), name: "signin-expired")
    }

    func testSettingsRenders() throws {
        try assertRenders(
            NavigationStack { SettingsView(email: "phu@example.com", signOut: {}) }, name: "settings")
    }
}
