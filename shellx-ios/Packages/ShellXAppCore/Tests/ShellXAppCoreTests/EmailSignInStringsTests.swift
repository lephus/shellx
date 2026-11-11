#if os(macOS)
import Foundation
import XCTest

/// The strings of sign-in with an emailed code are in the shared catalog, in English and Vietnamese, under the key
/// names the iPhone and Android both use.
final class EmailSignInStringsTests: XCTestCase {
    private static let keys = [
        "signin.email.continue",
        "signin.email.or",
        "signin.email.field",
        "signin.email.send",
        "signin.email.sentTo %@",
        "signin.email.code",
        "signin.email.verify",
        "signin.email.resend",
        "signin.email.resendIn %lld",
        "signin.email.change",
        "signin.error.invalidEmail",
        "signin.error.disposableEmail",
        "signin.error.invalidCode",
        "signin.error.codeExpired",
        "signin.error.emailSendFailed",
        "settings.account.method.email",
        "settings.account.delete.codeIntro",
        "settings.account.delete.codeField",
    ]

    func testEveryKeyIsTranslatedAndKeepsItsArgument() throws {
        let url = ScriptRunner.repositoryRoot.appendingPathComponent("shellx-ios/ShellX/Localizable.xcstrings")
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        XCTAssertEqual(Self.keys.count, 18)
        for key in Self.keys {
            let entry = try XCTUnwrap(strings[key], "missing \(key)")
            XCTAssertEqual(entry["extractionState"] as? String, "manual", key)
            XCTAssertFalse((entry["comment"] as? String ?? "").isEmpty, key)
            for language in ["en", "vi"] {
                let unit = ((entry["localizations"] as? [String: Any])?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) \(language)")
                let value = unit?["value"] as? String ?? ""
                XCTAssertFalse(value.isEmpty, "\(key) \(language)")
                for format in ["%@", "%lld"] {   // exactly the argument the key names, and no other
                    XCTAssertEqual(value.components(separatedBy: format).count - 1, key.hasSuffix(" " + format) ? 1 : 0, "\(key) \(language)")
                }
                XCTAssertNil(value.range(of: "iPhone|Apple|App Store|VoiceOver", options: .regularExpression), "\(key): Android imports this text")
            }
        }
    }
}
#endif
