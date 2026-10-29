import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphDiffOpenerTests: XCTestCase {
    func testCommitFileArgumentsUsePatchInputAndTitle() {
        let id = UUID()
        XCTAssertEqual(
            GitGraphDiffOpener.commitFileArguments(
                socketPath: "/s", patchPath: "/t/x.patch", repositoryRoot: "/r",
                workspaceId: id, title: "8429ad9 CLI/cmux.swift"
            ),
            ["--socket", "/s", "diff", "/t/x.patch", "--cwd", "/r", "--workspace", id.uuidString,
             "--title", "8429ad9 CLI/cmux.swift", "--focus", "true"]
        )
    }

    func testWorkingTreeArgumentsUseUnstagedSource() {
        let id = UUID()
        XCTAssertEqual(
            GitGraphDiffOpener.workingTreeArguments(socketPath: "/s", repositoryRoot: "/r", workspaceId: id),
            ["--socket", "/s", "diff", "--unstaged", "--cwd", "/r", "--workspace", id.uuidString, "--focus", "true"]
        )
    }

    func testTitleUsesShortShaAndPath() {
        XCTAssertEqual(
            GitGraphDiffOpener.title(sha: "8429ad9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", path: "CLI/cmux.swift"),
            "8429ad9 CLI/cmux.swift"
        )
    }

    func testWritePatchUsesPrivatePermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try GitGraphDiffOpener.writePatch(Data("diff --git a b\n".utf8), in: dir)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(url.pathExtension, "patch")
    }

    func testWritePatchResetsLooseExistingDirectoryPermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755]
        )
        _ = try GitGraphDiffOpener.writePatch(Data("x".utf8), in: dir)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int, 0o700)
    }

    func testSpawnFailureDeletesPatchImmediately() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try GitGraphDiffOpener.writePatch(Data("x".utf8), in: dir)
        let opened = GitGraphDiffOpener.launch(patchURL: url) { _ in false }
        XCTAssertFalse(opened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSpawnSuccessKeepsPatchUntilExit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try GitGraphDiffOpener.writePatch(Data("x".utf8), in: dir)
        var exitHandler: (@MainActor @Sendable () -> Void)?
        let opened = GitGraphDiffOpener.launch(patchURL: url) { onExit in
            exitHandler = onExit
            return true
        }
        XCTAssertTrue(opened)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        exitHandler?()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
