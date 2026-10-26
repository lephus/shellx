import CmuxFoundation
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
        tracker.setVisible(true)

        tracker.setTarget(.directory(a))
        tracker.setTarget(.directory(b))
        await tracker.resolutionTask?.value

        XCTAssertEqual(recorder.changedRoots, [b])
        XCTAssertEqual(controller.repositoryRoot, b)
        XCTAssertEqual(tracker.watchedRoot, b)
    }

    func testTrackerDropsResolutionSupersededDuringItsWalk() async throws {
        let (a, b) = try makeRepositories()
        let script = ScriptedWorkTreeRoots([a: [.root(a)], b: [.root(b)]], holding: a)
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = GitGraphRepositoryTracker(controller: controller, workTreeRoot: { await script.lookup($0) })
        tracker.setVisible(true)

        tracker.setTarget(.directory(a))
        await script.waitUntilHeld()
        tracker.setTarget(.directory(b))
        await script.release()
        await tracker.resolutionTask?.value

        let walksOfA = await script.lookupCount(a)
        XCTAssertEqual(walksOfA, 1)
        XCTAssertEqual(recorder.changedRoots, [b])
        XCTAssertEqual(tracker.watchedRoot, b)
    }

    func testFailedWalkIsRetriedForTheSameTargetOrPin() async throws {
        let (a, b) = try makeRepositories()
        let script = ScriptedWorkTreeRoots([a: [.unavailable, .unavailable, .root(a)], b: [.unavailable, .root(b)]])
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = GitGraphRepositoryTracker(controller: controller, workTreeRoot: { await script.lookup($0) })

        for _ in 0..<3 {
            tracker.setTarget(.directory(a))
            await tracker.resolutionTask?.value
        }
        XCTAssertEqual(controller.status, .ready)
        XCTAssertEqual(controller.repositoryRoot, a)
        // The repeated failure stayed silent.
        XCTAssertEqual(recorder.changedRoots, [nil, a])

        let pinned = GitGraphRepositoryTracker(controller: controller, workTreeRoot: { await script.lookup($0) })
        for _ in 0..<3 {
            pinned.pin(repositoryRoot: b)
            await pinned.resolutionTask?.value
        }
        XCTAssertEqual(controller.repositoryRoot, b)
        let walksOfB = await script.lookupCount(b)
        XCTAssertEqual(walksOfB, 2, "a pin of the same root is not walked again once it resolved")
    }

    func testBecomingVisibleRechecksAFolderThatWasNotARepository() async throws {
        let plain = try makeDirectory("plain")
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let tracker = controller.tracker

        tracker.setTarget(.directory(plain))
        await tracker.resolutionTask?.value
        XCTAssertEqual(controller.status, .notRepository)

        try gitInit(plain)
        tracker.setVisible(true)
        await tracker.resolutionTask?.value

        XCTAssertEqual(controller.status, .ready)
        XCTAssertEqual(controller.repositoryRoot, plain)
    }

    func testOpenAsTabPassesOnlyARepository() async {
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        var requestedRoots: [String?] = []
        controller.onOpenAsTab = { requestedRoots.append($0) }

        controller.showRepository(root: "/r/plain", status: .notRepository)
        XCTAssertNil(controller.readyRepositoryRoot)
        _ = await controller.handle(method: "history.openAsTab", params: [:])
        controller.showRepository(root: "/r/a", status: .ready)
        XCTAssertEqual(controller.readyRepositoryRoot, "/r/a")
        _ = await controller.handle(method: "history.openAsTab", params: [:])

        XCTAssertEqual(requestedRoots, [nil, "/r/a"])
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

    func testBecomingVisibleRefreshesOnceAndHiddenChangesAreIgnored() async throws {
        // A scripted root on a plain folder: the tracker treats it as a repository,
        // and no real watcher can add events of its own.
        let a = try makeDirectory("A")
        let script = ScriptedWorkTreeRoots([a: [.root(a)]])
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = GitGraphRepositoryTracker(controller: controller, workTreeRoot: { await script.lookup($0) })
        tracker.setTarget(.directory(a))
        await tracker.resolutionTask?.value

        tracker.repositoryFilesChanged()
        tracker.repositoryFilesChanged()
        XCTAssertEqual(recorder.invalidations, 0, "no refresh while hidden")

        tracker.setVisible(true)
        tracker.setVisible(true)
        XCTAssertEqual(recorder.invalidations, 1, "becoming visible refreshes once")

        // Nothing is tracked while hidden, so every return to view refreshes once.
        tracker.setVisible(false)
        tracker.setVisible(true)
        XCTAssertEqual(recorder.invalidations, 2)
    }

    func testHiddenTrackerResolvesButStartsNoWatcher() async throws {
        let (a, _) = try makeRepositories()
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let tracker = controller.tracker

        tracker.setTarget(.directory(a))
        await tracker.resolutionTask?.value
        XCTAssertEqual(controller.readyRepositoryRoot, a, "the root still resolves while hidden")
        XCTAssertNil(tracker.watchedRoot, "a Git tab that was never shown watches nothing")

        tracker.setVisible(true)
        XCTAssertEqual(tracker.watchedRoot, a)
        tracker.setVisible(false)
        XCTAssertNil(tracker.watchedRoot)
    }

    func testWatcherBurstWaitsForTheQuietPeriod() async throws {
        let a = try makeDirectory("A")
        let script = ScriptedWorkTreeRoots([a: [.root(a)]])
        let clock = GateClock()
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = GitGraphRepositoryTracker(
            controller: controller,
            workTreeRoot: { await script.lookup($0) },
            refreshClock: clock
        )
        tracker.setVisible(true)
        tracker.setTarget(.directory(a))
        await tracker.resolutionTask?.value
        XCTAssertEqual(recorder.invalidations, 0)

        // Each change restarts the wait, so only the last one's wait refreshes.
        for _ in 0..<5 {
            tracker.repositoryFilesChanged()
        }
        XCTAssertEqual(recorder.invalidations, 0, "a burst refreshes only after a quiet period")
        let last = try XCTUnwrap(tracker.pendingInvalidation)
        await clock.open()
        await last.value
        XCTAssertEqual(recorder.invalidations, 1)
        XCTAssertNil(tracker.pendingInvalidation)
        let durations = await clock.requestedDurations
        XCTAssertEqual(Set(durations), [.milliseconds(500)])
    }

    func testHidingDropsAPendingRefreshAndHiddenChangesScheduleNone() async throws {
        let a = try makeDirectory("A")
        let script = ScriptedWorkTreeRoots([a: [.root(a)]])
        let clock = GateClock()
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = GitGraphRepositoryTracker(
            controller: controller,
            workTreeRoot: { await script.lookup($0) },
            refreshClock: clock
        )
        tracker.setVisible(true)
        tracker.setTarget(.directory(a))
        await tracker.resolutionTask?.value

        tracker.repositoryFilesChanged()
        let pending = try XCTUnwrap(tracker.pendingInvalidation)
        tracker.setVisible(false)
        XCTAssertNil(tracker.pendingInvalidation)
        tracker.repositoryFilesChanged()
        XCTAssertNil(tracker.pendingInvalidation, "no refresh is scheduled while hidden")
        await clock.open()
        await pending.value
        XCTAssertEqual(recorder.invalidations, 0)
    }

    func testFailedFolderCheckShowsFailureAndRetryWalksAgain() async throws {
        let (a, _) = try makeRepositories()
        let script = ScriptedWorkTreeRoots([a: [.unavailable, .root(a)]])
        let controller = GitGraphController(placement: .sidebar, diffOpener: nil)
        let recorder = EventRecorder(controller)
        let tracker = GitGraphRepositoryTracker(controller: controller, workTreeRoot: { await script.lookup($0) })
        tracker.setTarget(.directory(a))
        await tracker.resolutionTask?.value

        // A walk that timed out or found the runner busy is not "git is missing".
        let failed = await controller.handle(method: "repo.state", params: [:])
        XCTAssertEqual((failed["error"] as? [String: Any])?["code"] as? String, "timedOut")

        // That repo.state is the page's Retry: it walks the folder again.
        await tracker.resolutionTask?.value
        XCTAssertEqual(controller.status, .ready)
        XCTAssertEqual(recorder.changedRoots, [nil, a])
        let walks = await script.lookupCount(a)
        XCTAssertEqual(walks, 2)
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

        // Opening without a repository keeps the tab's pin.
        let third = try XCTUnwrap(workspace.openOrFocusRightSidebarToolSurface(
            inPane: pane, mode: .git, focus: false, gitRepositoryRoot: nil
        ))
        XCTAssertEqual(third.id, first.id)
        XCTAssertEqual(third.pinnedGitRepositoryRoot, "/r/b")
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

/// Answers work-tree lookups from a per-directory script; the last answer repeats.
/// The first lookup of `holding` waits for ``release()``.
private actor ScriptedWorkTreeRoots {
    private var answers: [String: [GitWorkTreeRootLookup]]
    private var holding: String?
    private var counts: [String: Int] = [:]
    private var isHolding = false
    private var held: CheckedContinuation<Void, Never>?
    private var holdWaiter: CheckedContinuation<Void, Never>?

    init(_ answers: [String: [GitWorkTreeRootLookup]], holding: String? = nil) {
        self.answers = answers
        self.holding = holding
    }

    func lookup(_ directory: String) async -> GitWorkTreeRootLookup {
        counts[directory, default: 0] += 1
        if directory == holding {
            holding = nil
            isHolding = true
            holdWaiter?.resume()
            holdWaiter = nil
            await withCheckedContinuation { held = $0 }
        }
        guard var queue = answers[directory], let answer = queue.first else { return .notInRepository }
        if queue.count > 1 {
            queue.removeFirst()
            answers[directory] = queue
        }
        return answer
    }

    func lookupCount(_ directory: String) -> Int {
        counts[directory, default: 0]
    }

    /// Returns once the held lookup has started.
    func waitUntilHeld() async {
        guard !isHolding else { return }
        await withCheckedContinuation { holdWaiter = $0 }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

/// A refresh clock whose sleeps wait until ``open()``; from then on every sleep
/// returns at once. A cancelled sleeper still waits, as the tracker re-checks
/// cancellation after its sleep.
private actor GateClock: FileWatchClock {
    private(set) var requestedDurations: [Duration] = []
    private var isOpen = false
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        requestedDurations.append(duration)
        guard !isOpen else { return }
        await withCheckedContinuation { sleepers.append($0) }
    }

    func open() {
        isOpen = true
        for sleeper in sleepers {
            sleeper.resume()
        }
        sleepers.removeAll()
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
