#if os(macOS)
import Foundation
import XCTest

/// `scripts/shellx/check-ios-license.sh` keeps shellx-ios/ free of GPL code and network packages.
final class LicenseBoundaryTests: XCTestCase {
    private var script: String {
        ScriptRunner.repositoryRoot.appendingPathComponent("scripts/shellx/check-ios-license.sh").path
    }

    private let cleanManifest = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Core",
            dependencies: [.package(path: "../../../shellx-link")],
            targets: [.target(name: "Core", path: "Sources/Core")]
        )
        """

    private let cleanProject = """
        // !$*UTF8*$!
        {
        \tobjects = {
        \t\tA1 /* Base.xcconfig */ = {isa = PBXFileReference; path = Config/Base.xcconfig; sourceTree = "<group>"; };
        \t\tA2 /* XCLocalSwiftPackageReference */ = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Core; };
        \t};
        }
        """

    /// A tree that passes: one package on shellx-link, one project, app sources on allowed modules.
    private func makeCleanTree() throws -> URL {
        let root = try ScriptRunner.temporaryDirectory(for: self)
        try ScriptRunner.write(cleanManifest, to: "shellx-ios/Packages/Core/Package.swift", under: root)
        try ScriptRunner.write("public enum Core {}\n", to: "shellx-ios/Packages/Core/Sources/Core/Core.swift", under: root)
        try ScriptRunner.write(cleanProject, to: "shellx-ios/ShellX.xcodeproj/project.pbxproj", under: root)
        let app = ["import SwiftUI", "import ShellXAppCore", "@preconcurrency import ShellXLinkCore", ""]
        try ScriptRunner.write(app.joined(separator: "\n"), to: "shellx-ios/ShellX/App.swift", under: root)
        try ScriptRunner.write("@testable import ShellX\nimport XCTest\n", to: "shellx-ios/ShellXTests/T.swift", under: root)
        try ScriptRunner.write("// MIT\n", to: "shellx-link/Package.swift", under: root)
        return root
    }

    private func check(_ root: URL) throws -> ScriptRunner.Result {
        try ScriptRunner.run("bash", [script, "--root", root.path])
    }

    func testRepositoryPasses() throws {
        let result = try ScriptRunner.run("bash", [script])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testCleanFakeTreePasses() throws {
        let result = try check(try makeCleanTree())
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testRemotePackageInManifestFails() throws {
        let root = try makeCleanTree()
        let manifest = cleanManifest.replacingOccurrences(
            of: #".package(path: "../../../shellx-link")"#,
            with: #".package(url: "https://github.com/example/remote.git", from: "1.0.0")"#)
        try ScriptRunner.write(manifest, to: "shellx-ios/Packages/Core/Package.swift", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("shellx-ios/Packages/Core/Package.swift"), result.output)
    }

    func testRemotePackageInProjectFails() throws {
        let root = try makeCleanTree()
        let project = cleanProject.replacingOccurrences(
            of: "\t};\n}",
            with: "\t\tA3 = {isa = XCRemoteSwiftPackageReference; repositoryURL = \"https://github.com/example/remote\"; };\n\t};\n}")
        try ScriptRunner.write(project, to: "shellx-ios/ShellX.xcodeproj/project.pbxproj", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("shellx-ios/ShellX.xcodeproj/project.pbxproj"), result.output)
    }

    func testPathIntoGPLTreeFails() throws {
        let projectRoot = try makeCleanTree()
        let project = cleanProject.replacingOccurrences(
            of: "relativePath = Packages/Core;", with: "relativePath = ../Packages/iOS/Foo;")
        try ScriptRunner.write(project, to: "shellx-ios/ShellX.xcodeproj/project.pbxproj", under: projectRoot)

        let fromProject = try check(projectRoot)

        XCTAssertEqual(fromProject.status, 1, fromProject.output)
        XCTAssertTrue(fromProject.output.contains("../Packages/iOS/Foo"), fromProject.output)

        let manifestRoot = try makeCleanTree()
        let manifest = cleanManifest.replacingOccurrences(
            of: "../../../shellx-link", with: "../../../Packages/iOS/Foo")
        try ScriptRunner.write(manifest, to: "shellx-ios/Packages/Core/Package.swift", under: manifestRoot)

        let fromManifest = try check(manifestRoot)

        XCTAssertEqual(fromManifest.status, 1, fromManifest.output)
        XCTAssertTrue(fromManifest.output.contains("../../../Packages/iOS/Foo"), fromManifest.output)
    }

    func testImportOutsideAllowlistFails() throws {
        let root = try makeCleanTree()
        try ScriptRunner.write(
            "import SwiftUI\nimport CmuxMobileKit\n", to: "shellx-ios/ShellX/Feature.swift", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("shellx-ios/ShellX/Feature.swift"), result.output)
        XCTAssertTrue(result.output.contains("CmuxMobileKit"), result.output)
        XCTAssertFalse(result.output.contains("SwiftUI"), result.output)
    }

    // MARK: Imports the line-based check used to miss

    /// Writes `source` as an app file and expects the check to refuse it, naming the file.
    private func assertImportRefused(
        _ source: String, mentioning module: String? = "CmuxMobileKit",
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let root = try makeCleanTree()
        try ScriptRunner.write(source, to: "shellx-ios/ShellX/Feature.swift", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 1, "\(source)\n\(result.output)", file: file, line: line)
        XCTAssertTrue(result.output.contains("shellx-ios/ShellX/Feature.swift"), result.output, file: file, line: line)
        if let module {
            XCTAssertTrue(result.output.contains(module), "\(source)\n\(result.output)", file: file, line: line)
        }
    }

    func testSecondImportOnALineFails() throws {
        // Built from pieces, so this file never has a semicolon directly before an import itself.
        let semicolon = ";"
        try assertImportRefused("import SwiftUI\(semicolon) import CmuxMobileKit\n")
        try assertImportRefused("import SwiftUI\(semicolon)import CmuxMobileKit\n")
    }

    func testImportWithModuleOnNextLineFails() throws {
        try assertImportRefused("import\n    CmuxMobileKit\n", mentioning: nil)
        try assertImportRefused("@testable import\nCmuxMobileKit\n", mentioning: nil)
        try assertImportRefused("import struct\n    CmuxMobileKit.Foo\n", mentioning: nil)
    }

    func testEveryImportFormIsChecked() throws {
        let forms = [
            "@_exported import CmuxMobileKit\n",
            "@testable import CmuxMobileKit\n",
            "import struct CmuxMobileKit.Foo\n",
            "@_spi(Internal) @_implementationOnly import CmuxMobileKit\n",
            "@_spi(Internal)@testable import CmuxMobileKit\n",
            "public import CmuxMobileKit\n",
            "import\tCmuxMobileKit\n",
            "#if canImport(CmuxMobileKit)\n    @preconcurrency import CmuxMobileKit\n#endif\n",
            "/* vendored */ import CmuxMobileKit\n",
        ]
        for form in forms {
            try assertImportRefused(form)
        }
        try assertImportRefused("import `CmuxMobileKit`\n", mentioning: nil)
    }

    func testAllowedImportFormsPass() throws {
        let root = try makeCleanTree()
        let semicolon = ";"
        let source = [
            "import SwiftUI\(semicolon) import Foundation",
            "@_spi(Internal) @testable import ShellXAppCore",
            "public import struct Foundation.URL",
            "#if canImport(UIKit)",
            "    import UIKit",
            "#endif",
            // Neither comments, string literals nor `import` as an argument label are imports.
            "// import CmuxMobileKit",
            "/* import CmuxMobileKit */",
            "let note = \"import CmuxMobileKit\"",
            "let raw = #\"\"\"",
            "import CmuxMobileKit",
            "\"\"\"#",
            "func load(import value: Int) -> Int { value }",
            "let loaded = load(import: 1)",
            "",
        ].joined(separator: "\n")
        try ScriptRunner.write(source, to: "shellx-ios/ShellX/Feature.swift", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 0, result.output)
    }

    // MARK: Manifests the literal-only check used to miss

    private func manifest(dependencies: String = "", targets: String = "") -> String {
        "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"Core\",\n"
            + "    dependencies: [\(dependencies)],\n    targets: [\(targets)]\n)\n"
    }

    /// Writes `manifest` into the package as `name` and expects the check to refuse it.
    private func assertManifestRefused(
        _ manifest: String, named name: String = "Package.swift", file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let root = try makeCleanTree()
        try ScriptRunner.write(manifest, to: "shellx-ios/Packages/Core/\(name)", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 1, "\(manifest)\n\(result.output)", file: file, line: line)
        XCTAssertTrue(result.output.contains("shellx-ios/Packages/Core/\(name)"), result.output, file: file, line: line)
    }

    func testNetworkPackageInAnyFormFails() throws {
        let url = "\"https://github.com/example/remote.git\""
        try assertManifestRefused(
            "let u = \(url)\n" + manifest(dependencies: ".package(url: u, from: \"1.0.0\")"))
        try assertManifestRefused(manifest(dependencies: ".package(url: #\(url)#, from: \"1.0.0\")"))
        try assertManifestRefused(manifest(dependencies: "\n.package(\n    url: \(url),\n    from: \"1.0.0\"\n)\n"))
        try assertManifestRefused(manifest(dependencies: ".package(id: \"example.remote\", from: \"1.0.0\")"))
        try assertManifestRefused(manifest(dependencies: ".package(\n    id: \"example.remote\", from: \"1.0.0\")"))
        try assertManifestRefused(
            manifest(targets: ".binaryTarget(name: \"B\", url: \"https://example.com/b.zip\", checksum: \"0\")"))
        try assertManifestRefused(
            manifest(dependencies: ".package(url: \(url), from: \"1.0.0\")"), named: "Package@swift-6.0.swift")
    }

    func testManifestPathMustBeAStringLiteral() throws {
        let gpl = "\"../../../Packages/iOS/Foo\""
        try assertManifestRefused("let p = \(gpl)\n" + manifest(dependencies: ".package(path: p)"))
        try assertManifestRefused(manifest(dependencies: ".package(path: #\(gpl)#)"))
        try assertManifestRefused(manifest(dependencies: ".package(path: \"../../\" + \"../Packages/iOS/Foo\")"))
        try assertManifestRefused(manifest(dependencies: ".package(path: \"../../\"\n    + \"../Packages/iOS/Foo\")"))
        try assertManifestRefused(manifest(dependencies: ".package(path: \"\\(base)/Foo\")"))
        try assertManifestRefused(manifest(dependencies: ".package(path:\n    \"\"\"\n    ../../../Packages/iOS/Foo\n    \"\"\")"))
    }

    func testUnsafeFlagsInManifestFail() throws {
        let flags = ".target(name: \"Core\", linkerSettings: [.unsafeFlags([\"-L../../../Packages/iOS\"])])"
        try assertManifestRefused(manifest(targets: flags))
    }

    func testMultiLineLiteralPathPasses() throws {
        let root = try makeCleanTree()
        let formatted = manifest(dependencies: "\n        .package(\n            path: \"../../../shellx-link\"\n        ),\n    ")
        try ScriptRunner.write(formatted, to: "shellx-ios/Packages/Core/Package.swift", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 0, result.output)
    }

    // MARK: Symlinks and build-setting paths

    func testSymlinkFails() throws {
        let root = try makeCleanTree()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Packages/iOS/Foo"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("shellx-ios/ShellX/Vendor").path,
            withDestinationPath: "../../Packages/iOS/Foo")

        let result = try check(root)

        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("shellx-ios/ShellX/Vendor"), result.output)
    }

    func testBuildSettingInProjectPathFails() throws {
        let root = try makeCleanTree()
        let project = cleanProject.replacingOccurrences(
            of: "relativePath = Packages/Core;", with: "relativePath = \"$(SRCROOT)/../Packages/iOS/Foo\";")
        try ScriptRunner.write(project, to: "shellx-ios/ShellX.xcodeproj/project.pbxproj", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("$(SRCROOT)/../Packages/iOS/Foo"), result.output)
    }

    func testManaflowStringFails() throws {
        let root = try makeCleanTree()
        let name = "Mana" + "flow"
        try ScriptRunner.write("// Built by \(name)\n", to: "shellx-ios/ShellX/About.swift", under: root)

        let result = try check(root)

        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("shellx-ios/ShellX/About.swift"), result.output)
    }
}
#endif
