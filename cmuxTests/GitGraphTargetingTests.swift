import CmuxGit
import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphTargetingTests: XCTestCase {
    func testTargetPolicyPrefersLocalFocusedPanelAndReportsRemote() {
        XCTAssertEqual(GitGraphTargetPolicy.target(focusedPanelDirectory: "/r/a", focusedPanelIsRemote: false, usesRemoteDirectoryProvenance: false, presentedDirectory: "/r"), .directory("/r/a"))
        XCTAssertEqual(GitGraphTargetPolicy.target(focusedPanelDirectory: "/x", focusedPanelIsRemote: true, usesRemoteDirectoryProvenance: false, presentedDirectory: "/r"), .remote)
        XCTAssertEqual(GitGraphTargetPolicy.target(focusedPanelDirectory: nil, focusedPanelIsRemote: false, usesRemoteDirectoryProvenance: true, presentedDirectory: nil), .remote)
        XCTAssertEqual(GitGraphTargetPolicy.target(focusedPanelDirectory: "  ", focusedPanelIsRemote: false, usesRemoteDirectoryProvenance: false, presentedDirectory: nil), .none)
        XCTAssertEqual(GitGraphTargetPolicy.target(focusedPanelDirectory: nil, focusedPanelIsRemote: false, usesRemoteDirectoryProvenance: false, presentedDirectory: "/r"), .directory("/r"))
    }

    func testTrackerEmitsRepoChangedOnlyWhenRootChanges() async throws {
        let (a, b) = try makeRepositories()
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = controller.tracker

        tracker.setTarget(.directory(a + "/sub"))
        await tracker.resolutionTask?.value
        tracker.setTarget(.directory(a))
        await tracker.resolutionTask?.value
        tracker.setTarget(.directory(b))
        await tracker.resolutionTask?.value

        XCTAssertEqual(recorder.changedRoots, [a, b])
        XCTAssertEqual(controller.repositoryRoot, b)
        XCTAssertEqual(controller.status, .ready)
    }

    func testTrackerDropsSupersededResolution() async throws {
        let (a, b) = try makeRepositories()
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = controller.tracker

        tracker.setTarget(.directory(a))
        tracker.setTarget(.directory(b))
        await tracker.resolutionTask?.value

        XCTAssertEqual(recorder.changedRoots, [b])
        XCTAssertEqual(controller.repositoryRoot, b)
        XCTAssertEqual(tracker.watchedRoot, b)
    }

    func testTrackerMapsTargetsWithoutRepositoriesToStatuses() async throws {
        let (a, _) = try makeRepositories()
        let plain = try makeDirectory("plain")
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let tracker = controller.tracker

        tracker.setTarget(.remote)
        XCTAssertEqual(controller.status, .remote)
        XCTAssertNil(controller.repositoryRoot)

        // A walk from a deleted folder would climb into the repository above it.
        tracker.setTarget(.directory(a + "/deleted"))
        await tracker.resolutionTask?.value
        XCTAssertEqual(controller.status, .noDirectory)
        XCTAssertNil(controller.repositoryRoot)

        tracker.setTarget(.directory(plain))
        await tracker.resolutionTask?.value
        XCTAssertEqual(controller.status, .notRepository)
        XCTAssertEqual(controller.repositoryRoot, plain)
        XCTAssertNil(tracker.watchedRoot)

        tracker.setTarget(.none)
        XCTAssertEqual(controller.status, .noDirectory)
        XCTAssertNil(controller.repositoryRoot)
    }

    func testPinResolvesSavedPathAndIgnoresLaterTargets() async throws {
        let (a, b) = try makeRepositories()
        let controller = GitGraphController(placement: .tab, diffOpener: nil)
        let tracker = controller.tracker
        var resolvedRoots: [String] = []
        tracker.onResolveRoot = { resolvedRoots.append($0) }

        tracker.pin(repositoryRoot: a + "/sub")
        await tracker.resolutionTask?.value
        tracker.setTarget(.directory(b))
        await tracker.resolutionTask?.value

        XCTAssertEqual(controller.repositoryRoot, a)
        XCTAssertEqual(resolvedRoots, [a])
    }

    func testChangesWhileHiddenInvalidateOnceWhenShown() {
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = controller.tracker

        tracker.repositoryFilesChanged()
        tracker.repositoryFilesChanged()
        XCTAssertEqual(recorder.invalidations, 0)

        tracker.setVisible(true)
        XCTAssertEqual(recorder.invalidations, 1)
        tracker.setVisible(false)
        tracker.setVisible(true)
        XCTAssertEqual(recorder.invalidations, 1)

        tracker.repositoryFilesChanged()
        XCTAssertEqual(recorder.invalidations, 2)
    }

    func testSnapshotDecodesOldFormatAndRoundTripsRepositoryRoot() throws {
        let old = try JSONDecoder().decode(SessionRightSidebarToolPanelSnapshot.self, from: Data(#"{"mode":"git"}"#.utf8))
        XCTAssertEqual(old.mode, .git); XCTAssertNil(old.gitRepositoryRoot)
        let new = SessionRightSidebarToolPanelSnapshot(mode: .git, gitRepositoryRoot: "/r/a")
        XCTAssertEqual(try JSONDecoder().decode(SessionRightSidebarToolPanelSnapshot.self, from: JSONEncoder().encode(new)).gitRepositoryRoot, "/r/a")
    }

    func testOpenOrFocusRetargetsExistingGitTab() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let pane = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)

        let first = try XCTUnwrap(workspace.openOrFocusRightSidebarToolSurface(
            inPane: pane, mode: .git, focus: false, gitRepositoryRoot: "/r/a"
        ))
        XCTAssertEqual(first.pinnedGitRepositoryRoot, "/r/a")
        let second = try XCTUnwrap(workspace.openOrFocusRightSidebarToolSurface(
            inPane: pane, mode: .git, focus: false, gitRepositoryRoot: "/r/b"
        ))

        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.pinnedGitRepositoryRoot, "/r/b")
        let title = try XCTUnwrap(workspace.panelTitles[first.id])
        XCTAssertTrue(title.hasSuffix("b"), title)
        let tabId = try XCTUnwrap(workspace.surfaceIdFromPanelId(first.id))
        XCTAssertEqual(workspace.bonsplitController.tab(tabId)?.title, title)
        let snapshot = workspace.sessionSnapshot(includeScrollback: false)
        XCTAssertEqual(snapshot.panels.first { $0.id == first.id }?.rightSidebarTool?.gitRepositoryRoot, "/r/b")
    }

    // MARK: Fixtures

    /// Two repositories, A (with a `sub` folder) and B, as standardized paths.
    private func makeRepositories() throws -> (String, String) {
        let a = try makeDirectory("A")
        try FileManager.default.createDirectory(atPath: a + "/sub", withIntermediateDirectories: true)
        let b = try makeDirectory("B")
        try gitInit(a)
        try gitInit(b)
        return (a, b)
    }

    private func makeDirectory(_ name: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGraphTargetingTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let parent = url.deletingLastPathComponent()
        addTeardownBlock { try? FileManager.default.removeItem(at: parent) }
        return url.standardizedFileURL.path
    }

    private func gitInit(_ directory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "init", "-q", directory]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git init failed in \(directory)")
    }
}

/// Records the events a controller sends its page, with the root shown at each `repo.changed`.
@MainActor
private final class EventRecorder {
    private(set) var changedRoots: [String?] = []
    private(set) var invalidations = 0

    init(_ controller: GitGraphController) {
        controller.eventSink = { [weak self, weak controller] event in
            switch event["type"] as? String {
            case "repo.changed":
                self?.changedRoots.append(controller?.repositoryRoot)
            case "history.invalidated":
                self?.invalidations += 1
            default:
                break
            }
        }
    }
}
