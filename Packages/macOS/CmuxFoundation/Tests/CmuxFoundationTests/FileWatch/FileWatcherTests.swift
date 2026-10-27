import Foundation
import Testing

@testable import CmuxFoundation

@Suite struct FileWatcherTests {
    /// A watcher whose ancestor directory cannot be opened has to say so.
    ///
    /// `makeSource` returns nil when `open(O_EVTONLY)` fails and the watcher carries on, so the
    /// event stream exists with nothing behind it and can never yield. A caller waiting for a
    /// socket to be *created* would then wait forever, which is why the reconnect path reads this
    /// and falls back to its own retry loop rather than trusting the watch.
    /// Root ignores directory permissions, so the denial this test relies on cannot be staged there.
    @Test(.enabled(if: getuid() != 0)) func watcherReportsAFailedAncestorWatch() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-filewatch-denied-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            chmod(base.path, 0o755)
            try? FileManager.default.removeItem(at: base)
        }

        let watched = base.appendingPathComponent("socket")
        // 000 makes open(O_EVTONLY) fail with EACCES for a non-root user, which is the observable
        // stand-in for the fd exhaustion this guard actually exists to survive.
        #expect(chmod(base.path, 0o000) == 0)
        let denied = FileWatcher(path: watched.path)
        defer { Task { await denied.stop() } }
        #expect(await denied.isWatchingAncestorDirectory == false)
    }

    /// The positive half, so the property cannot pass by always returning false.
    @Test func watcherReportsAWorkingAncestorWatch() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-filewatch-ok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let watcher = FileWatcher(path: base.appendingPathComponent("socket").path)
        defer { Task { await watcher.stop() } }
        #expect(await watcher.isWatchingAncestorDirectory == true)
    }

    /// Awaits the watcher's first event, bounded so a broken watcher fails the
    /// test instead of hanging CI.
    private func firstEvent(_ watcher: FileWatcher, within seconds: Double) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = watcher.events.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    @Test func fileWriteYieldsEvent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("watched.txt")
        try "initial".write(to: file, atomically: true, encoding: .utf8)

        let watcher = FileWatcher(path: file.path)
        defer { Task { await watcher.stop() } }

        // Mutate after the watcher is listening (sources attach synchronously in init).
        try "changed".write(to: file, atomically: false, encoding: .utf8)

        #expect(await firstEvent(watcher, within: 5))
    }

    @Test func fileCreatedAfterStartYieldsEvent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("not-yet.txt")

        // Watch a path that does not exist yet; the parent-directory source must
        // recover when it is created.
        let watcher = FileWatcher(path: file.path)
        defer { Task { await watcher.stop() } }

        try "created".write(to: file, atomically: true, encoding: .utf8)

        #expect(await firstEvent(watcher, within: 5))
    }

    @Test func fileInNonexistentSubdirectoryRecoversViaAncestor() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Neither the intermediate directory nor the file exists yet; the watcher
        // must observe `root` (the nearest existing ancestor) and recover.
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        let file = nested.appendingPathComponent("watched.txt")

        let watcher = FileWatcher(path: file.path)
        defer { Task { await watcher.stop() } }

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "created".write(to: file, atomically: true, encoding: .utf8)

        #expect(await firstEvent(watcher, within: 5))
    }

    /// A directory created while the watcher attaches to the nearest existing ancestor raises no event on
    /// that ancestor. The watcher must not stay there: the path, created inside that directory afterwards,
    /// still yields. (The agent chat tailer watches a new session's transcript before Claude Code creates its
    /// project folder.) The race is real, so it is run many times.
    @Test func directoryCreatedWhileAttachingStillYieldsForThePath() async throws {
        var missed: [Int] = []
        for iteration in 0..<40 {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("cmux-file-watcher-race-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let nested = root.appendingPathComponent("a/b", isDirectory: true)
            let file = nested.appendingPathComponent("watched.txt")

            let box = WatcherBox()
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    box.set(FileWatcher(path: file.path))
                } else {
                    try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
                }
            }
            let watcher = try #require(box.watcher)
            let events = EventCount()
            let consumer = Task { for await _ in watcher.events { events.add() } }
            // Let any event the race itself raised arrive first.
            try? await Task.sleep(for: .milliseconds(100))
            let before = events.value

            try "created".write(to: file, atomically: false, encoding: .utf8)

            var yielded = false
            for _ in 0..<200 where !yielded {
                yielded = events.value > before
                if !yielded { try? await Task.sleep(for: .milliseconds(10)) }
            }
            if !yielded { missed.append(iteration) }
            consumer.cancel()
            await watcher.stop()
        }
        #expect(missed.isEmpty, "no event for the created path in iterations \(missed)")
    }

    @Test func directoryTargetYieldsOnChildChange() async throws {
        // The FileExplorer path: the watched path is itself a directory, and a
        // change to its contents must yield.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = FileWatcher(path: directory.path)
        defer { Task { await watcher.stop() } }

        try "child".write(to: directory.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)

        #expect(await firstEvent(watcher, within: 5))
    }

    @Test func atomicReplaceYieldsEvent() async throws {
        // The MarkdownPanel / JSONConfigStore save path: an atomic write replaces
        // the inode (temp file + rename), so the watcher must reattach via the
        // directory source and still yield.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("watched.txt")
        try "initial".write(to: file, atomically: true, encoding: .utf8)

        let watcher = FileWatcher(path: file.path)
        defer { Task { await watcher.stop() } }

        // `.atomic` writes to a sibling temp file then renames over the original,
        // replacing the inode the file source was attached to.
        try "replaced".write(to: file, atomically: true, encoding: .utf8)

        #expect(await firstEvent(watcher, within: 5))
    }

    @Test func throttledWatcherYieldsAfterChange() async throws {
        // A throttled watcher (the FileExplorer/MarkdownPanel coalescing config)
        // still delivers an event for a real change.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("watched.txt")
        try "initial".write(to: file, atomically: true, encoding: .utf8)

        let watcher = FileWatcher(path: file.path, throttle: .milliseconds(50))
        defer { Task { await watcher.stop() } }

        try "changed".write(to: file, atomically: false, encoding: .utf8)

        #expect(await firstEvent(watcher, within: 5))
    }

    @Test func stopFinishesStream() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-file-watcher-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("watched.txt")

        let watcher = FileWatcher(path: file.path)
        var iterator = watcher.events.makeAsyncIterator()
        await watcher.stop()
        let next: Void? = await iterator.next()
        #expect(next == nil)
    }
}

private final class WatcherBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: FileWatcher?
    func set(_ watcher: FileWatcher) { lock.lock(); stored = watcher; lock.unlock() }
    var watcher: FileWatcher? { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class EventCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
