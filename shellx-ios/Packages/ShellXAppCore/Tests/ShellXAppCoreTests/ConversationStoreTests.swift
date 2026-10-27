import XCTest

@testable import ShellXAppCore

final class ConversationStoreTests: XCTestCase {
    private struct Doc: Codable, Equatable, Sendable { var items: [String] }

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversation-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func ref(_ id: String, machine: String = "m1") -> SessionRef {
        SessionRef(machineID: machine, sessionId: id, agent: "claude", workspaceTitle: "w")
    }

    /// A store whose clock advances one second per call, so write order is deterministic.
    private func makeStore(maxThreads: Int = 100) -> ConversationStore {
        let ticks = Ticks()
        return ConversationStore(directory: directory, maxThreads: maxThreads, now: { ticks.next() })
    }

    func testRoundTripEachDocument() async {
        let store = makeStore()
        let docs: [StoreDocument] = [.home, .lastSessions, .thread(ref("s1"))]
        for (index, doc) in docs.enumerated() {
            await store.writer().save(Doc(items: ["a\(index)"]), to: doc)
        }
        for (index, doc) in docs.enumerated() {
            let loaded = await store.load(doc, as: Doc.self)
            XCTAssertEqual(loaded, Doc(items: ["a\(index)"]))
        }
        let missing = await store.load(.thread(ref("nope")), as: Doc.self)
        XCTAssertNil(missing)
        // A thread is found by machine and session id, not by the title or agent.
        let renamed = SessionRef(machineID: "m1", sessionId: "s1", agent: "codex", workspaceTitle: "other")
        let again = await store.load(.thread(renamed), as: Doc.self)
        XCTAssertEqual(again, Doc(items: ["a2"]))
        let otherMachine = await store.load(.thread(ref("s1", machine: "m2")), as: Doc.self)
        XCTAssertNil(otherMachine)
    }

    func testFileNames() async throws {
        let store = makeStore()
        await store.writer().save(Doc(items: []), to: .home)
        await store.writer().save(Doc(items: []), to: .lastSessions)
        await store.writer().save(Doc(items: []), to: .thread(ref("s1")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("home.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("last-sessions.json").path))
        let threads = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("threads").path)
        XCTAssertEqual(threads.count, 1)
        // sha256("m1\0s1") in hex plus ".json"; no session id in the name.
        XCTAssertEqual(threads[0].count, 64 + 5)
        XCTAssertFalse(threads[0].contains("s1"))
    }

    func testCorruptFileLoadsNilAndIsRemoved() async throws {
        let store = makeStore()
        await store.writer().save(Doc(items: ["x"]), to: .home)
        let file = directory.appendingPathComponent("home.json")
        try Data("{ not json".utf8).write(to: file)
        let loaded = await store.load(.home, as: Doc.self)
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        // The store keeps working afterwards.
        await store.writer().save(Doc(items: ["y"]), to: .home)
        let again = await store.load(.home, as: Doc.self)
        XCTAssertEqual(again, Doc(items: ["y"]))
    }

    func testThreadsBeyondLimitEvictOldest() async {
        let store = makeStore(maxThreads: 2)
        await store.writer().save(Doc(items: ["1"]), to: .thread(ref("s1")))
        await store.writer().save(Doc(items: ["2"]), to: .thread(ref("s2")))
        await store.writer().save(Doc(items: ["1b"]), to: .thread(ref("s1")))  // s2 is now the oldest write
        await store.writer().save(Doc(items: ["3"]), to: .thread(ref("s3")))
        let s1 = await store.load(.thread(ref("s1")), as: Doc.self)
        let s2 = await store.load(.thread(ref("s2")), as: Doc.self)
        let s3 = await store.load(.thread(ref("s3")), as: Doc.self)
        XCTAssertEqual(s1, Doc(items: ["1b"]))
        XCTAssertNil(s2)
        XCTAssertEqual(s3, Doc(items: ["3"]))
    }

    func testWipeRemovesEverything() async throws {
        let store = makeStore()
        await store.writer().save(Doc(items: ["a"]), to: .home)
        await store.writer().save(Doc(items: ["b"]), to: .thread(ref("s1")))
        try await store.wipe()
        let home = await store.load(.home, as: Doc.self)
        let thread = await store.load(.thread(ref("s1")), as: Doc.self)
        XCTAssertNil(home)
        XCTAssertNil(thread)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("home.json").path))
        // Saving works again after a wipe.
        await store.writer().save(Doc(items: ["c"]), to: .home)
        let again = await store.load(.home, as: Doc.self)
        XCTAssertEqual(again, Doc(items: ["c"]))
    }

    func testStaleWriterSaveAfterWipeWritesNothing() async throws {
        let store = makeStore()
        let stale = await store.writer()
        await stale.save(Doc(items: ["old"]), to: .home)
        try await store.wipe()
        await stale.save(Doc(items: ["late"]), to: .home)
        await stale.save(Doc(items: ["late"]), to: .thread(ref("s1")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let home = await store.load(.home, as: Doc.self)
        XCTAssertNil(home)
        // A writer made after the wipe works.
        let fresh = await store.writer()
        await fresh.save(Doc(items: ["new"]), to: .home)
        let loaded = await store.load(.home, as: Doc.self)
        XCTAssertEqual(loaded, Doc(items: ["new"]))
    }

    func testFailedWipeThrowsButStillInvalidatesWriters() async throws {
        // Make the delete fail: a read-only parent refuses to unlink the directory.
        let parent = directory.deletingLastPathComponent()
        let locked = parent.appendingPathComponent("locked-\(UUID().uuidString)", isDirectory: true)
        let inner = locked.appendingPathComponent("ShellX", isDirectory: true)
        let lockedStore = ConversationStore(directory: inner)
        let lockedWriter = await lockedStore.writer()
        await lockedWriter.save(Doc(items: ["a"]), to: .home)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: locked)
        }
        do {
            try await lockedStore.wipe()
            XCTFail("wipe should throw when the delete fails")
        } catch {}
        await lockedWriter.save(Doc(items: ["late"]), to: .home)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        // The delete emptied the directory before failing to unlink it; the stale write added nothing.
        let after = await lockedStore.load(.home, as: Doc.self)
        XCTAssertNil(after)
    }

    func testBackupExclusionIsSetAgainAfterWipe() async throws {
        let store = makeStore()
        await store.writer().save(Doc(items: []), to: .home)
        try await store.wipe()
        await store.writer().save(Doc(items: []), to: .home)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        // File protection (completeUntilFirstUserAuthentication) cannot be asserted under macOS
        // `swift test`; it is passed as a write option and verified on device only.
    }

    func testBackwardsClockNeverEvictsTheThreadJustSaved() async {
        let times = [3_000.0, 2_000.0, 1_000.0]  // each write is older than the one before
        let ticks = Ticks(times)
        let store = ConversationStore(directory: directory, maxThreads: 2, now: { ticks.next() })
        await store.writer().save(Doc(items: ["1"]), to: .thread(ref("s1")))
        await store.writer().save(Doc(items: ["2"]), to: .thread(ref("s2")))
        await store.writer().save(Doc(items: ["3"]), to: .thread(ref("s3")))
        let s3 = await store.load(.thread(ref("s3")), as: Doc.self)
        XCTAssertEqual(s3, Doc(items: ["3"]))
    }

    func testDirectoryExcludedFromBackup() async throws {
        let store = makeStore()
        await store.writer().save(Doc(items: []), to: .home)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}

private final class Ticks: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private let fixed: [Double]?
    init(_ fixed: [Double]? = nil) { self.fixed = fixed }
    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        if let fixed { return Date(timeIntervalSince1970: fixed[min(value, fixed.count) - 1]) }
        return Date(timeIntervalSince1970: 1_000_000 + Double(value))
    }
}
