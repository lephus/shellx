#if os(macOS)
import Foundation
import XCTest

/// `release/mobile/ios.sh --check-app --unsigned` on a fake app: an Info.plist and a tiny Mach-O whose strings the test picks.
final class ReleaseCheckTests: XCTestCase {
    private var script: String { ScriptRunner.repositoryRoot.appendingPathComponent("release/mobile/ios.sh").path }

    /// MARKETING_VERSION and CURRENT_PROJECT_VERSION of shellx-ios/Config/Version.xcconfig.
    private func version() throws -> (marketing: String, build: String) {
        let text = try String(contentsOf: ScriptRunner.repositoryRoot.appendingPathComponent("shellx-ios/Config/Version.xcconfig"), encoding: .utf8)
        func value(_ key: String) throws -> String {
            let line = try XCTUnwrap(text.split(separator: "\n").first { $0.hasPrefix(key) })
            return String(try XCTUnwrap(line.split(separator: "=").last)).trimmingCharacters(in: .whitespaces)
        }
        return (try value("MARKETING_VERSION"), try value("CURRENT_PROJECT_VERSION"))
    }

    private func makeApp(clientID: String = "123456789012-abcdef123.apps.googleusercontent.com", names: String = "ShellX") throws -> URL {
        let root = try ScriptRunner.temporaryDirectory(for: self)
        let app = root.appendingPathComponent("ShellX.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let (marketing, build) = try version()
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.shellx.prod", "CFBundleShortVersionString": marketing, "CFBundleVersion": build,
            "CFBundleExecutable": "ShellX", "ShellXGoogleClientID": clientID,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        try ScriptRunner.write("const char *volatile shellx_names = \"\(names)\";\nint main(void) { return shellx_names[0] == 0; }\n", to: "main.c", under: root)
        let cc = try ScriptRunner.run("xcrun", ["clang", "-x", "c", root.appendingPathComponent("main.c").path, "-o", app.appendingPathComponent("ShellX").path])
        XCTAssertEqual(cc.status, 0, cc.output)
        return app
    }
    private func check(_ app: URL) throws -> ScriptRunner.Result { try ScriptRunner.run("bash", [script, "--check-app", "--unsigned", app.path]) }

    func testRealGoogleClientPassesQuietly() throws {
        let result = try check(try makeApp())
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("not a Google iOS client id"), result.output)
    }

    func testPlaceholderGoogleClientIsOnlyNotedWhenUnsigned() throws {
        let result = try check(try makeApp(clientID: "0-shellx-placeholder.apps.googleusercontent.com"))
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("ShellXGoogleClientID is not a Google iOS client id yet"), result.output)
    }

    func testMissingGoogleBrandingIsOnlyNotedWhenUnsigned() throws {
        let result = try check(try makeApp())   // no Assets.car, no font
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("no Google “G” mark or Google Sans yet"), result.output)
    }

    func testDemoIsPartOfTheRelease() throws {
        let names = "FakeMac FakeMacFleet FakeMacDemoScript DemoComposition DemoScript DemoSession DemoRelay DemoSecretStore ShellXDemo"
        let result = try check(try makeApp(names: names))
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testDebugOnlyNamesAreRefused() throws {
        for name in ["FakeRelayAccount", "FakeIdentityProvider", "InMemorySecretStore", "FakeTranscriber", "FakeVoicePermissions", "SHELLX_DEMO", "ShellXAppTestSupport"] {
            let result = try check(try makeApp(names: name))
            XCTAssertEqual(result.status, 1, name)
            XCTAssertTrue(result.output.contains("contains Debug-only code: \(name)"), result.output)
        }
    }
    ```
}
#endif
