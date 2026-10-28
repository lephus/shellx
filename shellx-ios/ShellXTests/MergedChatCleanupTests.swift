import Foundation
import XCTest
@testable import ShellX

/// The one-time removal of the old merged "ShellX" chat's files (`AppComposition.removeMergedChatData`).
@MainActor
final class MergedChatCleanupTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("merged-chat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "MergedChatCleanupTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { [directory] in
            if let directory { try? FileManager.default.removeItem(at: directory) }
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    private func write(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func testRemovesTheMergedChatButKeepsTheAgentCopies() throws {
        let home = try write("home.json")
        let last = try write("last-sessions.json")
        let thread = try write("threads/0123abcd.json")

        AppComposition.removeMergedChatData(in: directory, defaults: defaults)

        XCTAssertFalse(exists(home))
        XCTAssertFalse(exists(last))
        XCTAssertTrue(exists(thread), "a single agent's chat copy is not part of the merged chat")
        XCTAssertTrue(defaults.bool(forKey: AppComposition.mergedChatRemovedKey))
    }

    func testRunsOnlyOnce() throws {
        AppComposition.removeMergedChatData(in: directory, defaults: defaults)
        let later = try write("home.json")

        AppComposition.removeMergedChatData(in: directory, defaults: defaults)

        XCTAssertTrue(exists(later), "the flag says it was done; later launches touch nothing")
    }

    func testNothingToRemoveStillMarksItDone() {
        let missing = directory.appendingPathComponent("never-made", isDirectory: true)

        AppComposition.removeMergedChatData(in: missing, defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: AppComposition.mergedChatRemovedKey))
    }

    func testAFileThatCannotBeRemovedIsTriedAgainNextLaunch() throws {
        let home = try write("home.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        addTeardownBlock { [directory] in
            if let directory { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        }

        AppComposition.removeMergedChatData(in: directory, defaults: defaults)

        XCTAssertTrue(exists(home))
        XCTAssertFalse(defaults.bool(forKey: AppComposition.mergedChatRemovedKey))

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        AppComposition.removeMergedChatData(in: directory, defaults: defaults)
        XCTAssertFalse(exists(home))
        XCTAssertTrue(defaults.bool(forKey: AppComposition.mergedChatRemovedKey))
    }
}
