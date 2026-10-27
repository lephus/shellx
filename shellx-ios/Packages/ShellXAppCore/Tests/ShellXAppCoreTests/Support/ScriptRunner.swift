#if os(macOS)
import Foundation
import XCTest

/// Runs one of the repository's check scripts and builds throwaway trees for them to check.
struct ScriptRunner {
    struct Result {
        var status: Int32
        var output: String
    }

    /// The repository root: the closest ancestor of this file holding `shellx-ios/` and `scripts/shellx/`.
    static let repositoryRoot: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent("shellx-ios").path),
               fm.fileExists(atPath: dir.appendingPathComponent("scripts/shellx").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        fatalError("repository root not found above \(#filePath)")
    }()

    /// Runs `executable` with `arguments` and returns its exit status and combined stdout and stderr.
    static func run(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// A new empty directory, removed when the test ends.
    static func temporaryDirectory(for testCase: XCTestCase) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-ios-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.resolvingSymlinksInPath()
    }

    /// Writes `text` to `relativePath` under `root`, creating directories as needed.
    static func write(_ text: String, to relativePath: String, under root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
