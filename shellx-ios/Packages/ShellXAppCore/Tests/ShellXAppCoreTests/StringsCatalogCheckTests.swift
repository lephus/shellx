#if os(macOS)
import Foundation
import XCTest

/// `shellx-ios/scripts/check-strings.py` keeps every visible string translated into English and Vietnamese.
final class StringsCatalogCheckTests: XCTestCase {
    private var script: String {
        ScriptRunner.repositoryRoot.appendingPathComponent("shellx-ios/scripts/check-strings.py").path
    }

    private static func unit(_ value: String, state: String = "translated") -> [String: Any] {
        ["stringUnit": ["state": state, "value": value]]
    }

    private static func plural(_ branches: [String: String]) -> [String: Any] {
        ["variations": ["plural": branches.mapValues { unit($0) }]]
    }

    /// The catalog of the clean tree, as `key -> entry`.
    private static func cleanStrings() -> [String: [String: Any]] {
        [
            "root.title": ["extractionState": "manual", "localizations": ["en": unit("ShellX"), "vi": unit("ShellX")]],
            "home.greeting": [
                "extractionState": "manual", "localizations": ["en": unit("Hello"), "vi": unit("Xin chào")],
            ],
            "agents.count %lld": [
                "extractionState": "manual",
                "localizations": [
                    "en": plural(["one": "%lld agent", "other": "%lld agents"]),
                    "vi": plural(["other": "%lld phiên agent"]),
                ],
            ],
        ]
    }

    private static let cleanSource = [
        "import SwiftUI",
        "",
        "struct HomeView: View {",
        "    let count: Int",
        "    var body: some View {",
        "        VStack {",
        "            Text(LocalizedStringResource(\"root.title\"))",
        "            Text(String(localized: \"home.greeting\"))",
        "            Text(String(localized: \"agents.count \\(count)\"))",
        "            Text(verbatim: \"2.0.0\")",
        "        }",
        "    }",
        "}",
        "",
    ].joined(separator: "\n")

    private func writeCatalog(_ strings: [String: [String: Any]], under root: URL) throws {
        let catalog: [String: Any] = ["sourceLanguage": "en", "version": "1.0", "strings": strings]
        let data = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
        try ScriptRunner.write(String(decoding: data, as: UTF8.self), to: "ShellX/Localizable.xcstrings", under: root)
    }

    /// A tree shaped like shellx-ios/ that passes the check.
    private func makeTree(
        strings: [String: [String: Any]]? = nil,
        source: String? = nil,
        identity: [String] = ["root.title"]
    ) throws -> URL {
        let root = try ScriptRunner.temporaryDirectory(for: self)
        try writeCatalog(strings ?? Self.cleanStrings(), under: root)
        try ScriptRunner.write(source ?? Self.cleanSource, to: "ShellX/UI/HomeView.swift", under: root)
        let identityFile = (["# keys whose Vietnamese text equals the English text"] + identity).joined(separator: "\n")
        try ScriptRunner.write(identityFile + "\n", to: "scripts/strings-identity.txt", under: root)
        return root
    }

    private func check(_ root: URL) throws -> ScriptRunner.Result {
        try ScriptRunner.run("python3", [script, "--root", root.path])
    }

    private func assertFails(
        _ root: URL, mentioning needle: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let result = try check(root)
        XCTAssertEqual(result.status, 1, result.output, file: file, line: line)
        XCTAssertTrue(result.output.contains(needle), "expected '\(needle)' in:\n\(result.output)", file: file, line: line)
    }

    func testRepositoryPasses() throws {
        let result = try ScriptRunner.run("python3", [script])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testCleanFakeTreePasses() throws {
        let result = try check(try makeTree())
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testMissingVietnameseFails() throws {
        var missing = Self.cleanStrings()
        missing["home.greeting"]?["localizations"] = ["en": Self.unit("Hello")]
        try assertFails(try makeTree(strings: missing), mentioning: "home.greeting")

        var untranslated = Self.cleanStrings()
        untranslated["home.greeting"]?["localizations"] = [
            "en": Self.unit("Hello"), "vi": Self.unit("Xin chào", state: "needs_review"),
        ]
        try assertFails(try makeTree(strings: untranslated), mentioning: "home.greeting")

        var empty = Self.cleanStrings()
        empty["home.greeting"]?["localizations"] = ["en": Self.unit("Hello"), "vi": Self.unit("")]
        try assertFails(try makeTree(strings: empty), mentioning: "home.greeting")

        var missingBranch = Self.cleanStrings()
        missingBranch["agents.count %lld"]?["localizations"] = [
            "en": Self.plural(["other": "%lld agents"]), "vi": Self.plural(["other": "%lld phiên agent"]),
        ]
        try assertFails(try makeTree(strings: missingBranch), mentioning: "agents.count %lld")

        var missingEnglish = Self.cleanStrings()
        missingEnglish["home.greeting"]?["localizations"] = ["vi": Self.unit("Xin chào")]
        try assertFails(try makeTree(strings: missingEnglish), mentioning: "home.greeting")
    }

    func testStaleEntryFails() throws {
        var strings = Self.cleanStrings()
        strings["home.greeting"]?["extractionState"] = "stale"
        try assertFails(try makeTree(strings: strings), mentioning: "home.greeting")
    }

    func testCopiedEnglishFails() throws {
        var strings = Self.cleanStrings()
        strings["home.greeting"]?["localizations"] = ["en": Self.unit("Hello"), "vi": Self.unit("Hello")]
        try assertFails(try makeTree(strings: strings), mentioning: "home.greeting")
    }

    func testIdentityListAllowsSameText() throws {
        var strings = Self.cleanStrings()
        strings["home.greeting"]?["localizations"] = ["en": Self.unit("Hello"), "vi": Self.unit("Hello")]

        let result = try check(try makeTree(strings: strings, identity: ["root.title", "home.greeting"]))

        XCTAssertEqual(result.status, 0, result.output)
    }

    func testKeyMissingFromCatalogFails() throws {
        let source = Self.cleanSource.replacingOccurrences(
            of: "Text(verbatim: \"2.0.0\")", with: "Text(String(localized: \"home.missing\"))")
        try assertFails(try makeTree(source: source), mentioning: "home.missing")

        let resource = Self.cleanSource.replacingOccurrences(
            of: "Text(verbatim: \"2.0.0\")", with: "Text(LocalizedStringResource(\"home.other\"))")
        try assertFails(try makeTree(source: resource), mentioning: "home.other")
    }

    func testBareTextLiteralFails() throws {
        let literals = [
            "Text(\"Hello\")", "Button(\"Go\") {}", "Label(\"Mac\", systemImage: \"laptopcomputer\")",
            ".navigationTitle(\"Home\")", ".alert(\"Oops\", isPresented: .constant(true)) {}",
        ]
        for literal in literals {
            let source = Self.cleanSource.replacingOccurrences(of: "Text(verbatim: \"2.0.0\")", with: literal)
            try assertFails(try makeTree(source: source), mentioning: "ShellX/UI/HomeView.swift:10")
        }
    }
}
#endif
