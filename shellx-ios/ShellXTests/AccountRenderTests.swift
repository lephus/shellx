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
            SignInView(coordinator: .preview(), expired: false, initialError: .switchFromSignedInDevice), name: "signin-error")
    }

    func testSignInWithNoticeRenders() throws {
        try assertRenders(SignInView(coordinator: .preview(), expired: false, notice: .appleLinkDenied), name: "signin-notice")
    }

    func testEveryFailureHasItsOwnWords() {
        let errors: [SignInError] = [
            .invalidCredentials, .rateLimited, .network, .server(code: "x"), .localWipePending, .switchFromSignedInDevice,
            .emailInUse, .identityInUse, .reauthRequired, .providerUnavailable, .providerFailed, .switchToGoogleFirst,
        ]
        let messages = errors.compactMap(SignInErrorText.message(for:))
        XCTAssertEqual(messages.count, errors.count)
        XCTAssertEqual(Set(messages).count, errors.count, "each failure says something different")
        let notices: [SignInNotice] = [.appleLinkDenied, .appleLinkExpired, .appleLinkFailed]
        XCTAssertEqual(Set(notices.map(SignInErrorText.message(for:))).count, 3)
    }

    func testCancelledHasNoMessage() {
        XCTAssertNil(SignInErrorText.message(for: .cancelled))
    }

    func testSignInButtonsRender() throws {
        try assertRenders(
            VStack(spacing: 12) { GoogleSignInButton(action: {}); AppleSignInButton(action: {}).frame(height: 44); Spacer() }
                .padding(16).background(Color.appBackground),
            name: "signin-buttons")
        try assertRenders(
            VStack(spacing: 12) { GoogleSignInButton(busy: true, action: {}); Spacer() }.padding(16).background(Color.appBackground),
            name: "signin-buttons-busy")
    }

    func testGoogleMarkIsTheOfficialSizeOnceBundled() throws {
        try XCTSkipIf(GoogleSignInButton.mark == nil, "Task 9 Step 7 adds the GoogleG asset")
        XCTAssertEqual(GoogleSignInButton.mark?.size, CGSize(width: 20, height: 20))
    }

    func testGoogleSansIsUsedOnceBundled() throws {
        let font = Bundle.main.url(forResource: "GoogleSans", withExtension: "ttf")
            ?? Bundle.main.url(forResource: "GoogleSans", withExtension: "ttf", subdirectory: "Fonts")
        try XCTSkipIf(font == nil, "Task 9 Step 7 bundles Google Sans")
        XCTAssertNotNil(UIFont(name: "GoogleSans-Regular", size: 14))
        XCTAssertTrue(GoogleSignInButton.labelFont().fontName.hasPrefix("GoogleSans"), GoogleSignInButton.labelFont().fontName)
        XCTAssertEqual(GoogleSignInButton.labelFont().pointSize, 14)
    }
    ```

    func testSignInExpiredRenders() throws {
        try assertRenders(SignInView(coordinator: .preview(), expired: true), name: "signin-expired")
    }

    func testSettingsRenders() throws {
        try assertRenders(
            NavigationStack { SettingsView(email: "phu@example.com", signOut: {}) }, name: "settings")
    }

    func testLicensesLinkToTheWebsiteAndShowItsHost() {
        XCTAssertEqual(AboutSection.website.absoluteString, "https://shellx.pro")
        XCTAssertEqual(AboutSection.websiteHost, AboutSection.website.host())
    }
}
