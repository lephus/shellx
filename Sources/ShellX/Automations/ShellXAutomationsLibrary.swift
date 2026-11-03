import Foundation
import Observation
import os
import ShellXAutomations

/// The app's view of every saved automation and skill, kept current by watching the
/// store's change stamp.
///
/// The store replaces `changeStampURL` after every mutation, also from `shellx routine run`
/// in another process, so a change to its folder means "reload". The first load also
/// reconciles the launchd jobs with what is on disk.
@MainActor
@Observable
final class ShellXAutomationsLibrary {
    private(set) var automations: [ShellXAutomation] = []

    /// Every automation and skill, including skills ShellX did not create.
    var count: Int { automations.count }

    /// Cronjobs and workflows whose newest run the user has not seen.
    var unreadCount: Int { automations.filter { $0.lastRun?.unread == true }.count }

    @ObservationIgnored private let store: ShellXAutomationStore
    @ObservationIgnored private let scheduler: ShellXLaunchAgentScheduler
    @ObservationIgnored private let changeStampURL: URL
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var reloadAgain = false
    @ObservationIgnored private var source: (any DispatchSourceFileSystemObject)?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "pro.shellx.desktop", category: "automations")

    init(store: ShellXAutomationStore, scheduler: ShellXLaunchAgentScheduler, changeStampURL: URL) {
        self.store = store
        self.scheduler = scheduler
        self.changeStampURL = changeStampURL
    }

    /// Reads the store again. Overlapping calls coalesce into one more read. A failed read keeps the last list.
    func reload() async {
        if isReloading {
            reloadAgain = true
            return
        }
        isReloading = true
        defer { isReloading = false }
        repeat {
            reloadAgain = false
            do {
                let loaded = try await store.list()
                if loaded != automations { automations = loaded }
                if !hasLoaded {
                    hasLoaded = true
                    await syncSchedules(loaded)
                }
            } catch {
                logger.error("automations.reload failed: \(String(describing: error), privacy: .public)")
            }
        } while reloadAgain
    }

    /// Loads once and reloads whenever the store's folder changes, until ``stopWatching()``.
    func startWatching() {
        guard watchTask == nil else { return }
        let folder = changeStampURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        if descriptor >= 0 {
            // Carve-out: DispatchSource is the only file-system watcher; it stays behind the `changes` stream.
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: .global(qos: .utility)
            )
            source.setEventHandler { continuation.yield() }
            source.setCancelHandler {
                close(descriptor)
                continuation.finish()
            }
            source.resume()
            self.source = source
        } else {
            logger.error("automations.watch could not open \(folder.path, privacy: .public)")
        }
        watchTask = Task { [weak self] in
            await self?.reload()
            for await _ in changes {
                guard let self else { return }
                await self.reload()
            }
        }
    }

    /// Stops watching the store's folder.
    func stopWatching() {
        source?.cancel()
        source = nil
        watchTask?.cancel()
        watchTask = nil
    }

    private func syncSchedules(_ automations: [ShellXAutomation]) async {
        do {
            try await scheduler.sync(automations)
        } catch let error as ShellXLaunchAgentSyncError {
            for failure in error.failures {
                logger.error("automations.sync \(failure.id, privacy: .public): \(failure.message, privacy: .public)")
            }
        } catch {
            logger.error("automations.sync failed: \(String(describing: error), privacy: .public)")
        }
    }
}
