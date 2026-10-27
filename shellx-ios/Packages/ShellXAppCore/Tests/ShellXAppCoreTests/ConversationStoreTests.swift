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
            await store.save(Doc(items: ["a\(index)"]), to: doc)
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
        await store.save(Doc(items: []), to: .home)
        await store.save(Doc(items: []), to: .lastSessions)
        await store.save(Doc(items: []), to: .thread(ref("s1")))
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
        await store.save(Doc(items: ["x"]), to: .home)
        let file = directory.appendingPathComponent("home.json")
        try Data("{ not json".utf8).write(to: file)
        let loaded = await store.load(.home, as: Doc.self)
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        // The store keeps working afterwards.
        await store.save(Doc(items: ["y"]), to: .home)
        let again = await store.load(.home, as: Doc.self)
        XCTAssertEqual(again, Doc(items: ["y"]))
    }

    func testThreadsBeyondLimitEvictOldest() async {
        let store = makeStore(maxThreads: 2)
        await store.save(Doc(items: ["1"]), to: .thread(ref("s1")))
        await store.save(Doc(items: ["2"]), to: .thread(ref("s2")))
        await store.save(Doc(items: ["1b"]), to: .thread(ref("s1")))  // s2 is now the oldest write
        await store.save(Doc(items: ["3"]), to: .thread(ref("s3")))
        let s1 = await store.load(.thread(ref("s1")), as: Doc.self)
        let s2 = await store.load(.thread(ref("s2")), as: Doc.self)
        let s3 = await store.load(.thread(ref("s3")), as: Doc.self)
        XCTAssertEqual(s1, Doc(items: ["1b"]))
        XCTAssertNil(s2)
        XCTAssertEqual(s3, Doc(items: ["3"]))
    }

    func testWipeRemovesEverything() async {
        let store = makeStore()
        await store.save(Doc(items: ["a"]), to: .home)
        await store.save(Doc(items: ["b"]), to: .thread(ref("s1")))
        await store.wipe()
        let home = await store.load(.home, as: Doc.self)
        let thread = await store.load(.thread(ref("s1")), as: Doc.self)
        XCTAssertNil(home)
        XCTAssertNil(thread)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("home.json").path))
        // Saving works again after a wipe.
        await store.save(Doc(items: ["c"]), to: .home)
        let again = await store.load(.home, as: Doc.self)
        XCTAssertEqual(again, Doc(items: ["c"]))
    }

    func testDirectoryExcludedFromBackup() async throws {
        let store = makeStore()
        await store.save(Doc(items: []), to: .home)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}

private final class Ticks: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return Date(timeIntervalSince1970: 1_000_000 + Double(value))
    }
}
