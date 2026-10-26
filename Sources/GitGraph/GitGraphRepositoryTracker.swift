import CmuxFoundation
import CmuxGit
import Foundation

/// Points a ``GitGraphController`` at the work tree that holds a target directory,
/// and tells it when that repository's Git metadata changes.
///
/// The sidebar's tracker follows the focused terminal through ``setTarget(_:)``. A
/// tab's tracker is pinned to one repository by ``pin(repositoryRoot:)`` and ignores
/// targets from then on.
///
/// The controller is told only about real changes: a target that resolves to the
/// root and status already shown (a `cd` inside the same repository) is silent, and
/// a resolution that finishes after a newer target was set is dropped.
///
/// An unchanged target is resolved again only when the last walk failed
/// (`.gitUnavailable`, usually because another walk held the shared runner), and on
/// becoming visible also after `.notRepository` (`git init` in place). A repeated
/// answer stays silent.
///
/// Targets resolve whether or not the page is on screen, because ⤢ and the command
/// palette need the root. Watching runs only while it is: there is no refresh while
/// hidden, and becoming visible refreshes once.
@MainActor
final class GitGraphRepositoryTracker {
    /// Looks up the work tree that holds a directory. Tests substitute a script.
    typealias WorkTreeRootLookup = @Sendable (_ directory: String) async -> GitWorkTreeRootLookup

    /// Called with the work-tree root each time a resolution finds one.
    var onResolveRoot: ((_ root: String) -> Void)?
    /// The resolution in flight, if any. Tests await it.
    private(set) var resolutionTask: Task<Void, Never>?
    /// The root whose Git metadata is watched: the shown root while it is `.ready`
    /// and the page is visible.
    private(set) var watchedRoot: String?
    /// The refresh waiting for the watcher to go quiet, if any. Tests await it.
    private(set) var pendingInvalidation: Task<Void, Never>?

    private weak var controller: GitGraphController?
    private let metadata: GitMetadataService
    private let workTreeRoot: WorkTreeRootLookup
    private let refreshClock: any FileWatchClock
    private let refreshQuietPeriod: Duration
    private var isPinned = false
    private var target: GitGraphTarget?
    /// Bumped for every new target. A resolution started for an older one is dropped.
    private var resolutionGeneration: UInt64 = 0
    private var shown: Shown?
    private var watcher: RecursivePathWatcher?
    private var watcherTask: Task<Void, Never>?
    private var isVisible = false

    /// Work-tree walks share one runner app-wide, which answers `.unavailable` to a
    /// walk started while another is running. Every tracker's walks queue here.
    private static var walkQueueTail: Task<Void, Never>?

    private struct Shown: Equatable {
        let root: String?
        let status: GitGraphRepoStatus
    }

    /// - Parameters:
    ///   - refreshClock: Waits out ``refreshQuietPeriod``. Tests substitute a clock they release by hand.
    ///   - refreshQuietPeriod: How long the watcher must stay quiet before the page refreshes.
    init(
        controller: GitGraphController,
        metadata: GitMetadataService = GitMetadataService(),
        workTreeRoot: WorkTreeRootLookup? = nil,
        refreshClock: any FileWatchClock = SystemFileWatchClock(),
        refreshQuietPeriod: Duration = .milliseconds(500)
    ) {
        self.controller = controller
        self.metadata = metadata
        self.workTreeRoot = workTreeRoot ?? { directory in
            await metadata.workTreeRoot(forDirectory: directory)
        }
        self.refreshClock = refreshClock
        self.refreshQuietPeriod = refreshQuietPeriod
    }

    deinit {
        pendingInvalidation?.cancel()
        watcherTask?.cancel()
        if let watcher {
            Task { await watcher.stop() }
        }
    }

    /// Follows `target`. Does nothing once pinned, or when `target` is the current one
    /// and its last walk did not fail.
    func setTarget(_ target: GitGraphTarget) {
        guard !isPinned, target != self.target || lastWalkFailed else { return }
        resolve(target)
    }

    /// Shows the work tree that holds `repositoryRoot` from now on. The path is
    /// resolved like a target's directory, so a saved subdirectory shows its work
    /// tree's top level and a deleted folder shows `.noDirectory`. Pinning the same
    /// path again resolves it again only when its last walk failed.
    func pin(repositoryRoot: String) {
        let target = GitGraphTarget.directory(repositoryRoot)
        guard !isPinned || target != self.target || lastWalkFailed else { return }
        isPinned = true
        resolve(target)
    }

    /// Watching runs only while visible. Nothing is tracked while hidden, so
    /// becoming visible refreshes a shown repository once. It also retries a failed
    /// walk, and re-checks a folder that was not a repository.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        guard visible else {
            cancelPendingInvalidation()
            updateWatcher()
            return
        }
        updateWatcher()
        if shown?.status == .ready {
            controller?.notifyInvalidated()
        }
        if let target, lastWalkFailed || shown?.status == .notRepository {
            resolve(target)
        }
    }

    /// Called for each coalesced change the watcher reports. The page refreshes
    /// once the changes stop for ``refreshQuietPeriod``; nothing happens while hidden.
    func repositoryFilesChanged() {
        guard isVisible else { return }
        pendingInvalidation?.cancel()
        let clock = refreshClock
        let quietPeriod = refreshQuietPeriod
        pendingInvalidation = Task { [weak self] in
            do {
                try await clock.sleep(for: quietPeriod)
            } catch {
                return
            }
            // A later change restarted the wait, or the page was hidden.
            guard !Task.isCancelled, let self else { return }
            self.pendingInvalidation = nil
            self.controller?.notifyInvalidated()
        }
    }

    private func cancelPendingInvalidation() {
        pendingInvalidation?.cancel()
        pendingInvalidation = nil
    }

    // MARK: Resolution

    private var lastWalkFailed: Bool {
        shown?.status == .gitUnavailable
    }

    private func resolve(_ target: GitGraphTarget) {
        self.target = target
        resolutionGeneration &+= 1
        let generation = resolutionGeneration
        switch target {
        case .none:
            resolutionTask = nil
            show(root: nil, status: .noDirectory)
        case .remote:
            resolutionTask = nil
            show(root: nil, status: .remote)
        case .directory(let directory):
            let previousWalk = Self.walkQueueTail
            let workTreeRoot = workTreeRoot
            let task = Task { [weak self] in
                await previousWalk?.value
                // A newer target arrived while this one waited its turn.
                guard self?.resolutionGeneration == generation else { return }
                let resolved = await Self.resolution(of: directory, workTreeRoot: workTreeRoot)
                guard let self, self.resolutionGeneration == generation else { return }
                self.show(root: resolved.root, status: resolved.status)
            }
            Self.walkQueueTail = task
            resolutionTask = task
        }
    }

    /// Resolves `directory` off the main actor.
    nonisolated private static func resolution(
        of directory: String,
        workTreeRoot: WorkTreeRootLookup
    ) async -> (root: String?, status: GitGraphRepoStatus) {
        let lookup = await workTreeRoot(directory)
        // The walk is bounded, so a hung mount ends here; a plain stat of it would
        // block a thread (and the walk queue) with no timeout.
        if lookup == .unavailable {
            return (nil, .gitUnavailable)
        }
        // A walk from a deleted folder climbs into the repository above it, so its
        // answer counts only for a folder that exists.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return (nil, .noDirectory)
        }
        switch lookup {
        case .root(let root):
            return (root, .ready)
        case .notInRepository:
            return (directory, .notRepository)
        case .unavailable:
            return (nil, .gitUnavailable)
        }
    }

    private func show(root: String?, status: GitGraphRepoStatus) {
        let next = Shown(root: root, status: status)
        if next != shown {
            shown = next
            // Showing another repository reloads the page anyway.
            cancelPendingInvalidation()
            controller?.showRepository(root: root, status: status)
        }
        updateWatcher()
        if status == .ready, let root {
            onResolveRoot?(root)
        }
    }

    // MARK: Watching

    private func updateWatcher() {
        watch(isVisible && shown?.status == .ready ? shown?.root : nil)
    }

    private func watch(_ root: String?) {
        guard root != watchedRoot else { return }
        watcherTask?.cancel()
        watcherTask = nil
        if let watcher {
            Task { await watcher.stop() }
        }
        watcher = nil
        watchedRoot = root
        guard let root else { return }
        let metadata = metadata
        watcherTask = Task { [weak self] in
            guard let watcher = await Self.makeWatcher(root: root, metadata: metadata) else { return }
            guard !Task.isCancelled, let self, self.watchedRoot == root else {
                await watcher.stop()
                return
            }
            self.watcher = watcher
            self.watcherTask = self.consumeEvents(of: watcher)
        }
    }

    /// Watches the repository's Git metadata from the sidebar's watch plan (HEAD,
    /// index, refs, packed-refs, reftable and config), not its work tree: editing a
    /// tracked file refreshes nothing until it reaches the index. The plan's
    /// `watchedPaths` lists the paths that existed when it was built, so keeping the
    /// metadata paths found there needs no filesystem call here.
    nonisolated private static func makeWatcher(
        root: String,
        metadata: GitMetadataService
    ) async -> RecursivePathWatcher? {
        guard let descriptor = await metadata.watchDescriptor(for: root) else { return nil }
        let existing = Set(descriptor.watchedPaths)
        return await RecursivePathWatcher(
            paths: descriptor.gitMetadataPaths.filter(existing.contains),
            eventFilter: { descriptor.containsGitMetadataChange(
                paths: $0.paths, requiresFullRescan: $0.requiresFullRescan
            ) }
        )
    }

    private func consumeEvents(of watcher: RecursivePathWatcher) -> Task<Void, Never> {
        let events = watcher.events
        return Task { [weak self] in
            for await _ in events {
                guard let self, !Task.isCancelled else { break }
                self.repositoryFilesChanged()
            }
        }
    }
}
