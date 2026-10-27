import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite(.serialized)
struct ShellXWorkspaceSetTests {
    // MARK: - Store

    @Test func saveListGetDeleteRoundTripKeepsWorkspaceOrder() throws {
        let context = try TemporaryWorkspaceSetContext()
        defer { context.cleanup() }
        let store = WorkspaceSetStore(fileURL: context.fileURL)

        try store.save(Self.set(named: "Daily", folders: ["/p/a", "/p/b", "/p/c"]), overwrite: false)

        #expect(try store.list().map(\.name) == ["Daily"])
        let loaded = try #require(try store.set(named: "daily"))
        #expect(loaded.workspaces.map(\.cwd) == ["/p/a", "/p/b", "/p/c"])

        try store.delete(named: "DAILY")
        #expect(try store.list().isEmpty)
    }

    @Test func reopenedStoreReadsSetsWrittenByAnotherInstance() throws {
        let context = try TemporaryWorkspaceSetContext()
        defer { context.cleanup() }
        try WorkspaceSetStore(fileURL: context.fileURL)
            .save(Self.set(named: "Daily", folders: ["/p/a", "/p/b"]), overwrite: false)

        let loaded = try #require(try WorkspaceSetStore(fileURL: context.fileURL).set(named: "Daily"))
        #expect(loaded.workspaces.map(\.cwd) == ["/p/a", "/p/b"])
    }

    @Test func duplicateNameRejectedWithoutOverwriteAndReplacedWithOverwrite() throws {
        let context = try TemporaryWorkspaceSetContext()
        defer { context.cleanup() }
        let store = WorkspaceSetStore(fileURL: context.fileURL)

        try store.save(Self.set(named: "Daily", folders: ["/p/a"]), overwrite: false)
        do {
            try store.save(Self.set(named: "daily", folders: ["/p/b"]), overwrite: false)
            Issue.record("Expected duplicate save to fail")
        } catch WorkspaceSetStoreError.duplicateName(let name) {
            #expect(name == "daily")
        }

        try store.save(Self.set(named: "daily", folders: ["/p/b"]), overwrite: true)
        #expect(try store.list().count == 1)
        #expect(try store.set(named: "DAILY")?.workspaces.map(\.cwd) == ["/p/b"])
    }

    @Test func blankNameRejected() throws {
        let context = try TemporaryWorkspaceSetContext()
        defer { context.cleanup() }
        let store = WorkspaceSetStore(fileURL: context.fileURL)

        do {
            try store.save(Self.set(named: "  ", folders: ["/p/a"]), overwrite: false)
            Issue.record("Expected blank name save to fail")
        } catch WorkspaceSetStoreError.blankName {
            #expect(try store.list().isEmpty)
        }
    }

    @Test func deletingMissingSetReportsNotFound() throws {
        let context = try TemporaryWorkspaceSetContext()
        defer { context.cleanup() }
        let store = WorkspaceSetStore(fileURL: context.fileURL)

        do {
            try store.delete(named: "Missing")
            Issue.record("Expected delete of a missing set to fail")
        } catch WorkspaceSetStoreError.notFound(let name) {
            #expect(name == "Missing")
        }
    }

    @Test func corruptFileThrowsAndSaveRefusesToClobber() throws {
        let context = try TemporaryWorkspaceSetContext()
        defer { context.cleanup() }
        try "{ not json".write(to: context.fileURL, atomically: true, encoding: .utf8)
        let store = WorkspaceSetStore(fileURL: context.fileURL)

        do {
            _ = try store.list()
            Issue.record("Expected corrupt file to fail")
        } catch WorkspaceSetStoreError.corruptFile {
            #expect(true)
        }

        do {
            try store.save(Self.set(named: "Daily", folders: ["/p/a"]), overwrite: false)
            Issue.record("Expected save to refuse a corrupt file")
        } catch WorkspaceSetStoreError.corruptFile {
            #expect(try String(contentsOf: context.fileURL, encoding: .utf8) == "{ not json")
        }
    }

    // MARK: - Which workspaces a new set saves

    @Test func multiSelectionOfTwoOrMoreSavesOnlySelectedInSidebarOrder() {
        let ids = (0..<4).map { _ in UUID() }

        let saved = WorkspaceSetPlan.workspaceIdsToSave(
            orderedIds: ids,
            selectedIds: [ids[3], ids[1]]
        )

        #expect(saved == [ids[1], ids[3]])
    }

    @Test func singleOrEmptySelectionSavesEveryWorkspace() {
        let ids = (0..<3).map { _ in UUID() }

        #expect(WorkspaceSetPlan.workspaceIdsToSave(orderedIds: ids, selectedIds: [ids[1]]) == ids)
        #expect(WorkspaceSetPlan.workspaceIdsToSave(orderedIds: ids, selectedIds: []) == ids)
    }

    // MARK: - Which saved workspaces to open

    @Test func openingSkipsFoldersThatAlreadyHaveAWorkspace() {
        let indices = WorkspaceSetPlan.indicesToOpen(
            savedDirectories: ["/p/a", "~/p/b", "/p/c/", "/p/d"],
            openDirectories: ["/p/c", "/home/me/p/b"],
            homeDirectory: "/home/me"
        )

        #expect(indices == [0, 3])
    }

    @Test func openingKeepsSavedOrderAndRepeatedFolders() {
        let indices = WorkspaceSetPlan.indicesToOpen(
            savedDirectories: ["/p/b", "/p/a", "/p/b"],
            openDirectories: [],
            homeDirectory: "/home/me"
        )

        #expect(indices == [0, 1, 2])
    }

    @Test func savedWorkspaceWithoutFolderIsAlwaysOpened() {
        let indices = WorkspaceSetPlan.indicesToOpen(
            savedDirectories: [nil, "/p/a"],
            openDirectories: ["/home/me", "/p/a"],
            homeDirectory: "/home/me"
        )

        #expect(indices == [0])
    }

    // MARK: - Helpers

    private static func set(named name: String, folders: [String]) -> CmuxWorkspaceSet {
        CmuxWorkspaceSet(
            name: name,
            workspaces: folders.map { CmuxWorkspaceDefinition(cwd: $0) }
        )
    }
}

struct TemporaryWorkspaceSetContext {
    let directoryURL: URL
    let fileURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("workspace-sets.json", isDirectory: false)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
