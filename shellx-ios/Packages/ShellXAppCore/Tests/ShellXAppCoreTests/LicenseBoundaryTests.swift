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
