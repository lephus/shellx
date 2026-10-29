import CmuxAgentChat
import Foundation
import Testing
@testable import CmuxMobileHost

/// A tailer created before its transcript exists: a new Claude Code session names the file in its first hooks
/// and writes it after them, so every line it writes is live, from the first one.
@Suite("Agent chat transcript tailer", .serialized, .timeLimit(.minutes(1)))
struct AgentChatTranscriptTailerTests {
    /// The batches one tailer published.
    private final class Batches: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [AgentChatTranscriptTailer.Batch] = []
        func record(_ batch: AgentChatTranscriptTailer.Batch) { lock.lock(); recorded.append(batch); lock.unlock() }
        var appendedIDs: [String] { lock.lock(); defer { lock.unlock() }; return recorded.flatMap(\.appended).map(\.id) }
        var titles: [String] { lock.lock(); defer { lock.unlock() }; return recorded.compactMap(\.discoveredTitle) }
        var resets: Int { lock.lock(); defer { lock.unlock() }; return recorded.filter(\.didReset).count }
    }

    private static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func userLine(_ uuid: String, _ text: String) -> String {
        json(["type": "user", "message": ["role": "user", "content": text], "uuid": uuid,
              "timestamp": "2026-10-27T05:00:00.000Z", "sessionId": "s"])
    }

    private static func assistantLine(_ uuid: String, _ text: String) -> String {
        json(["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": text]]],
              "uuid": uuid, "timestamp": "2026-10-27T05:00:01.000Z", "sessionId": "s"])
    }

    /// A transcript path in a project folder that does not exist yet.
    private static func missingTranscript() throws -> (home: URL, file: URL) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("tailer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return (home, home.appendingPathComponent("projects/-tmp-new/\(UUID().uuidString).jsonl"))
    }

    private static func append(_ lines: [String], to file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
        try handle.close()
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @Test func testTranscriptCreatedAfterStartIsPublishedFromItsFirstLine() async throws {
        let (home, file) = try Self.missingTranscript()
        defer { try? FileManager.default.removeItem(at: home) }
        let batches = Batches()
        let tailer = AgentChatTranscriptTailer(sessionID: "s", agentKind: .claude, path: file.path) { batches.record($0) }
        await tailer.start()

        try Self.append([Self.userLine("u-1", "Create the file")], to: file)
        try Self.append([Self.assistantLine("a-1", "Created")], to: file)

        #expect(await Self.waitUntil { batches.appendedIDs.count >= 2 })
        #expect(batches.titles == ["Create the file"])
        let page = await tailer.history(beforeSeq: nil, limit: 50)
        #expect(page.messages.map(\.seq) == [0, 1])
        #expect(page.hasMore == false)
        await tailer.stop()
    }

    /// The file appears between the tailer's creation and its start: what the agent wrote then is still live.
    @Test func testTranscriptCreatedBeforeStartIsPublished() async throws {
        let (home, file) = try Self.missingTranscript()
        defer { try? FileManager.default.removeItem(at: home) }
        let batches = Batches()
        let tailer = AgentChatTranscriptTailer(sessionID: "s", agentKind: .claude, path: file.path) { batches.record($0) }

        try Self.append([Self.userLine("u-1", "Create the file"), Self.assistantLine("a-1", "Created")], to: file)
        await tailer.start()

        #expect(await Self.waitUntil { batches.appendedIDs.count >= 2 })
        try Self.append([Self.userLine("u-2", "Thanks")], to: file)
        #expect(await Self.waitUntil { batches.appendedIDs.count >= 3 })
        await tailer.stop()
    }

    /// A transcript that first appears already holding a whole history (cmux's Claude fork writes the parent's
    /// history into the new session's file after SessionStart) is backfilled, not pushed as one huge batch:
    /// clients are told to re-anchor, history pages it, and later lines are live again.
    @Test func testLateTranscriptOverTheByteBudgetIsBackfilled() async throws {
        let (home, file) = try Self.missingTranscript()
        defer { try? FileManager.default.removeItem(at: home) }
        let batches = Batches()
        let tailer = AgentChatTranscriptTailer(sessionID: "s", agentKind: .claude, path: file.path) { batches.record($0) }
        await tailer.start()

        let padding = String(repeating: "x", count: 40)
        let history = (0..<3000).map { Self.userLine("u-\($0)", "Earlier prompt \($0) \(padding)") }
        try Self.append(history, to: file)

        #expect(await Self.waitUntil { batches.resets > 0 })
        #expect(batches.appendedIDs.isEmpty)
        let page = await tailer.history(beforeSeq: nil, limit: 50)
        #expect(page.messages.last?.seq == 2999)
        #expect(page.hasMore)
        try Self.append([Self.assistantLine("a-1", "Live again")], to: file)
        #expect(await Self.waitUntil { batches.appendedIDs.count == 1 })
        await tailer.stop()
    }

    /// The same for a first write under the byte budget but over the backfill line bound.
    @Test func testLateTranscriptOverTheLineBoundIsBackfilled() async throws {
        let (home, file) = try Self.missingTranscript()
        defer { try? FileManager.default.removeItem(at: home) }
        let batches = Batches()
        let tailer = AgentChatTranscriptTailer(sessionID: "s", agentKind: .claude, path: file.path,
                                               maxInitialLines: 10) { batches.record($0) }
        await tailer.start()

        try Self.append((0..<30).map { Self.userLine("u-\($0)", "Prompt \($0)") }, to: file)

        #expect(await Self.waitUntil { batches.resets > 0 })
        #expect(batches.appendedIDs.isEmpty)
        let page = await tailer.history(beforeSeq: nil, limit: 50)
        #expect(page.messages.map(\.seq) == Array(20..<30))
        #expect(page.hasMore)
        await tailer.stop()
    }

    /// A tailer that never saw its transcript says so; once the file appeared it does not, even if the file is
    /// later removed (its cache still serves history).
    @Test func testWaitingForTranscriptUntilTheFileAppears() async throws {
        let (home, file) = try Self.missingTranscript()
        defer { try? FileManager.default.removeItem(at: home) }
        let batches = Batches()
        let tailer = AgentChatTranscriptTailer(sessionID: "s", agentKind: .claude, path: file.path) { batches.record($0) }
        await tailer.start()
        #expect(await tailer.isWaitingForTranscript)

        try Self.append([Self.userLine("u-1", "Create the file")], to: file)
        #expect(await Self.waitUntil { !batches.appendedIDs.isEmpty })
        #expect(await tailer.isWaitingForTranscript == false)
        try FileManager.default.removeItem(at: file)
        #expect(await tailer.isWaitingForTranscript == false)
        #expect(await tailer.history(beforeSeq: nil, limit: 10).messages.count == 1)
        await tailer.stop()

        let existing = AgentChatTranscriptTailer(sessionID: "s", agentKind: .claude, path: #filePath) { _ in }
        #expect(await existing.isWaitingForTranscript == false)
    }

    /// An existing transcript is backfilled, not published: only later lines are live.
    @Test func testExistingTranscriptIsBackfilledNotPublished() async throws {
        let (home, file) = try Self.missingTranscript()
        defer { try? FileManager.default.removeItem(at: home) }
        try Self.append([Self.userLine("u-1", "Old prompt")], to: file)
        let batches = Batches()
        let tailer = AgentChatTranscriptTailer(sessionID: "s", agentKind: .claude, path: file.path) { batches.record($0) }
        await tailer.start()

        try Self.append([Self.assistantLine("a-1", "New answer")], to: file)

        #expect(await Self.waitUntil { !batches.appendedIDs.isEmpty })
        #expect(batches.appendedIDs.count == 1)
        #expect(await tailer.history(beforeSeq: nil, limit: 50).messages.count == 2)
        await tailer.stop()
    }
}
