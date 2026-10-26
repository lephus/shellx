import CmuxFoundation
import CmuxGit
import Foundation

/// Points a ``GitGraphController`` at the work tree that holds a target directory,
/// and tells it when that work tree's files change.
///
/// The sidebar's tracker follows the focused terminal through ``setTarget(_:)``. A
/// tab's tracker is pinned to one repository by ``pin(repositoryRoot:)`` and ignores
/// targets from then on.
///
/// The controller is told only about real changes: a target that resolves to the
/// root and status already shown (a `cd` inside the same repository) is silent, and
/// a resolution that finishes after a newer target was set is dropped.
@MainActor
final class GitGraphRepositoryTracker {
    /// Called with the work-tree root each time a resolution finds one.
    var onResolveRoot: ((_ root: String) -> Void)?
    /// The resolution in flight, if any. Tests await it.
    private(set) var resolutionTask: Task<Void, Never>?
    /// The root whose files are watched: the shown root while it is `.ready`.
    private(set) var watchedRoot: String?

    private weak var controller: GitGraphController?
    private let metadata: GitMetadataService
    private var isPinned = false
    private var target: GitGraphTarget?
    /// Bumped for every new target. A resolution started for an older one is dropped.
    private var resolutionGeneration: UInt64 = 0
    private var shown: Shown?
    private var watcher: RecursivePathWatcher?
    private var watcherTask: Task<Void, Never>?
    private var isVisible = false
    private var hasChangesWhileHidden = false

    /// Work-tree walks share one runner app-wide, which answers `.unavailable` to a
    /// walk started while another is running. Every tracker's walks queue here.
    private static var walkQueueTail: Task<Void, Never>?

    private struct Shown: Equatable {
        let root: String?
        let status: GitGraphRepoStatus
    }

    init(controller: GitGraphController, metadata: GitMetadataService = GitMetadataService()) {
        self.controller = controller
        self.metadata = metadata
    }

    deinit {
        watcherTask?.cancel()
        if let watcher {
            Task { await watcher.stop() }
        }
    }

    /// Follows `target`. Does nothing once pinned, or when `target` is the current one.
    func setTarget(_ target: GitGraphTarget) {
        guard !isPinned, target != self.target else { return }
        resolve(target)
    }

    /// Shows the work tree that holds `repositoryRoot` from now on. The path is
    /// resolved like a target's directory, so a saved subdirectory shows its work
    /// tree's top level and a deleted folder shows `.noDirectory`.
    func pin(repositoryRoot: String) {
        isPinned = true
        resolve(.directory(repositoryRoot))
    }

    /// Changes while hidden are remembered; becoming visible after one reloads once.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        guard visible, hasChangesWhileHidden else { return }
        hasChangesWhileHidden = false
        controller?.notifyInvalidated()
    }

    /// Called for each coalesced change the watcher reports.
    func repositoryFilesChanged() {
        guard isVisible else {
            hasChangesWhileHidden = true
            return
        }
        controller?.notifyInvalidated()
    }

    // MARK: Resolution

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
            let metadata = metadata
            let task = Task { [weak self] in
                await previousWalk?.value
                // A newer target arrived while this one waited its turn.
                guard self?.resolutionGeneration == generation else { return }
                let resolved = await Self.resolution(of: directory, metadata: metadata)
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
        metadata: GitMetadataService
    ) async -> (root: String?, status: GitGraphRepoStatus) {
        let lookup = await metadata.workTreeRoot(forDirectory: directory)
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
            hasChangesWhileHidden = false
            controller?.showRepository(root: root, status: status)
        }
        watch(status == .ready ? root : nil)
        if status == .ready, let root {
            onResolveRoot?(root)
        }
    }

    // MARK: Watching

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

    /// Built the way `SidebarGitMetadataService` builds its watchers.
    nonisolated private static func makeWatcher(
        root: String,
        metadata: GitMetadataService
    ) async -> RecursivePathWatcher? {
        guard let descriptor = await metadata.watchDescriptor(for: root) else { return nil }
        return await RecursivePathWatcher(
            paths: descriptor.watchedPaths,
            throttleInterval: descriptor.eventCoalescingInterval,
            eventFilter: { descriptor.containsRelevantChange(
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
