import ShellXAppCore
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

    /// Debug keeps plain HTTP to the local network for the loopback relay (`SHELLX_API_BASE`); the
    /// App Store build must not have it, which `ios.sh --check-app` refuses (final review, Minor 5).
    func testDebugBuildAllowsTheLocalRelay() {
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        XCTAssertEqual(ats?["NSAllowsLocalNetworking"] as? Bool, true)
    }

    func testGoogleClientIDComesFromTheBuildSettings() {
        let id = Bundle.main.object(forInfoDictionaryKey: "ShellXGoogleClientID") as? String
        XCTAssertEqual(id?.hasSuffix(".apps.googleusercontent.com"), true, id ?? "nil")
        XCTAssertEqual(id?.contains("$("), false, "the build setting was expanded")
    }

    @MainActor
    func testPlaceholderClientMakesGoogleUnavailable() async {
        let provider = SystemIdentityProvider(googleClientID: "0-shellx-placeholder.apps.googleusercontent.com")
        do { _ = try await provider.googleIDToken(nonce: "n"); XCTFail("signed in without a client") } catch {
            XCTAssertEqual(error as? IdentityProviderError, .notConfigured)
        }
    }

    @MainActor
    func testRootRenders() throws {
        let images = try SnapshotWriter().write(RootView(graph: .preview(), inbox: PairingInbox()), name: "root")

        XCTAssertEqual(images.count, 2)
        for image in images {
            XCTAssertEqual(image.size, SnapshotWriter.size)
        }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }
}
