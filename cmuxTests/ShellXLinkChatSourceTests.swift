import CMUXAgentLaunch
import CmuxAgentChat
import CmuxMobileHost
import Foundation
import ShellXLinkCore
import ShellXLinkSession
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX Link's `AgentChatSource` over the agent chat transcript service: history pages, live entries, and
/// the send / interrupt commands a phone runs.
@Suite("ShellX Link chat source", .serialized, .timeLimit(.minutes(1)))
struct ShellXLinkChatSourceTests {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []
        func record(_ call: String) { lock.lock(); recorded.append(call); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    }

    /// The pushes one `entries()` subscriber received, filled by its consumer task.
    private final class Pushes: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [(sessionId: String, entries: [ChatEntry])] = []
        func record(_ push: (sessionId: String, entries: [ChatEntry])) { lock.lock(); recorded.append(push); lock.unlock() }
        var entries: [ChatEntry] { lock.lock(); defer { lock.unlock() }; return recorded.flatMap(\.entries) }
    }

    private static func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-link-chat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A service over a private hook store with no mobile client subscribed.
    @MainActor
    private static func makeService(home: URL) -> AgentChatTranscriptService {
        AgentChatTranscriptService(
            registry: AgentChatSessionRegistry(hookStore: AgentChatHookSessionStore(homeDirectory: home)),
            resolver: AgentChatTranscriptResolver(homeDirectory: home, environment: [:]),
            hasEventSubscribers: { false },
            emitEventPayload: { _ in }
        )
    }

    private static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func userLine(_ uuid: String, _ text: String) -> String {
        json(["type": "user", "message": ["role": "user", "content": text], "uuid": uuid,
              "timestamp": "2026-10-27T05:00:00.000Z", "sessionId": "s"])
    }

    private static func assistantLine(_ uuid: String, _ blocks: [[String: Any]]) -> String {
        json(["type": "assistant", "message": ["role": "assistant", "content": blocks], "uuid": uuid,
              "timestamp": "2026-10-27T05:00:01.000Z", "sessionId": "s"])
    }

    /// A Claude session (or `source`) whose transcript holds `lines`.
    @MainActor
    private static func addSession(_ service: AgentChatTranscriptService, home: URL, lines: [String],
                                   source: String = "claude") throws -> (id: String, transcript: URL) {
        let id = UUID().uuidString
        let transcript = home.appendingPathComponent("\(id).jsonl")
        try lines.map { $0 + "\n" }.joined().write(to: transcript, atomically: true, encoding: .utf8)
        service.noteHookEvent(WorkstreamEvent(sessionId: id, hookEventName: .sessionStart, source: source,
                                              transcriptPath: transcript.path, cwd: "/Users/example/project"))
        return (id, transcript)
    }

    @MainActor
    private static func tailerActive(_ service: AgentChatTranscriptService, _ sessionID: String) -> Bool {
        service.debugSessionDump().first { $0["session_id"] as? String == sessionID }?["tailer_active"] as? Bool ?? false
    }

    @MainActor
    private static func waitUntil(seconds: Double = 5, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @Test func testHistoryMapsMessages() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let service = await MainActor.run { Self.makeService(home: home) }
        let source = await MainActor.run { ShellXLinkChatSource(service: { service }) }
        let (session, codex) = try await MainActor.run { () throws -> (String, String) in
            let claude = try Self.addSession(service, home: home, lines: [
                Self.userLine("u-1", "Fix the build"),
                Self.assistantLine("a-1", [
                    ["type": "text", "text": "Looking into it"],
                    ["type": "thinking", "thinking": "The linker fails"],
                    ["type": "tool_use", "id": "t-read", "name": "Read", "input": ["file_path": "/tmp/a.swift"]],
                    ["type": "tool_use", "id": "t-bash", "name": "Bash", "input": ["command": "swift build"]],
                    ["type": "tool_use", "id": "t-edit", "name": "Edit",
                     "input": ["file_path": "/tmp/a.swift", "old_string": "a", "new_string": "b"]],
                ]),
            ])
            let codex = try Self.addSession(service, home: home, lines: [Self.userLine("u-1", "hi")], source: "codex")
            return (claude.id, codex.id)
        }

        let page = try #require(await source.history(sessionId: session, beforeSeq: nil, limit: 50))

        #expect(page.hasMore == false)
        let entries = page.entries
        let user = try #require(entries.first)
        #expect(user.role == .user)
        #expect(user.kind == .prose)
        #expect(user.text == "Fix the build")
        #expect(user.seq == 0)
        #expect(user.tsMs == 1_793_077_200_000)   // 2026-10-27T05:00:00Z
        #expect(user.truncated == nil)
        let agent = entries.dropFirst()
        #expect(agent.allSatisfy { $0.role == .agent && $0.seq == 1 })
        #expect(agent.first { $0.kind == .prose }?.text == "Looking into it")
        #expect(agent.first { $0.kind == .thought }?.text == "The linker fails")
        let tools = agent.filter { $0.kind == .toolUse }
        #expect(tools.map(\.toolName) == ["Read", "Bash", "Edit"])
        #expect(tools.map(\.text) == ["Read /tmp/a.swift", "swift build", "/tmp/a.swift"])
        // Every emission carries a revision; a later emission of the same entry carries a higher one.
        #expect(Set(entries.map(\.id)).count == entries.count)
        let again = try #require(await source.history(sessionId: session, beforeSeq: nil, limit: 50)).entries
        #expect(again.map(\.id) == entries.map(\.id))
        #expect(zip(entries, again).allSatisfy { $1.rev > $0.rev })
        // Claude Code only, and an unknown session has no history.
        #expect(await source.history(sessionId: codex, beforeSeq: nil, limit: 50) == nil)
        #expect(await source.history(sessionId: "no-such-session", beforeSeq: nil, limit: 50) == nil)
    }

    @Test func testEntryTextCutTo4096Bytes() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let service = await MainActor.run { Self.makeService(home: home) }
        let source = await MainActor.run { ShellXLinkChatSource(service: { service }) }
        let long = "x" + String(repeating: "€", count: 5000)   // 15 001 bytes; 4096 falls inside a character
        let session = try await MainActor.run {
            try Self.addSession(service, home: home, lines: [Self.assistantLine("a-1", [["type": "text", "text": long]])]).id
        }

        let entry = try #require(await source.history(sessionId: session, beforeSeq: nil, limit: 50)?.entries.first)

        #expect(entry.text.utf8.count <= ChatEntry.maxTextBytes)
        #expect(entry.text.utf8.count > ChatEntry.maxTextBytes - 3)
        #expect(long.hasPrefix(entry.text))
        #expect(entry.truncated == true)
    }

    /// `chat.send` and `chat.interrupt` run the same `TerminalController` functions as `mobile.chat.send` and
    /// `mobile.chat.interrupt`, and their errors map to Link outcomes.
    @Test func testSendUsesSharedPathAndMapsBusy() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let service = await MainActor.run { Self.makeService(home: home) }
        let calls = Calls()
        let sendResults: [TerminalController.V2CallResult] = [
            .err(code: "input_queue_full", message: "full", data: nil),
            .err(code: "busy", message: "busy", data: nil),
            .err(code: "not_found", message: "moved", data: nil),
            .err(code: "surface_unavailable", message: "gone", data: nil),
            .ok(["submitted": true]),
            .ok(["submitted": false, "submit_error": "surface_changed"]),
        ]
        let interruptResults: [TerminalController.V2CallResult] = [
            .ok(["interrupted": true]),
            .err(code: "not_found", message: "moved", data: nil),
            .err(code: "surface_unavailable", message: "no", data: nil),
        ]
        let (source, session, codex) = try await MainActor.run { () throws -> (ShellXLinkChatSource, String, String) in
            var sends = sendResults[...]
            var interrupts = interruptResults[...]
            let source = ShellXLinkChatSource(
                service: { service },
                send: { sessionID, text in
                    calls.record("send \(sessionID) \(text)")
                    return sends.popFirst() ?? .err(code: "internal_error", message: "", data: nil)
                },
                interrupt: { sessionID, hard in
                    calls.record("interrupt \(sessionID) \(hard)")
                    return interrupts.popFirst() ?? .err(code: "internal_error", message: "", data: nil)
                }
            )
            let session = try Self.addSession(service, home: home, lines: []).id
            let codex = try Self.addSession(service, home: home, lines: [], source: "codex").id
            return (source, session, codex)
        }

        var outcomes: [ChatSendOutcome] = []
        for _ in sendResults { outcomes.append(await source.send(sessionId: session, text: "hello")) }
        #expect(outcomes == [.busy, .busy, .notFound, .failed, .submitted, .failed])
        #expect(await source.interrupt(sessionId: session, hard: true) == .sent)
        #expect(await source.interrupt(sessionId: session, hard: false) == .notFound)
        #expect(await source.interrupt(sessionId: session, hard: false) == .failed)
        // Another agent's session, or one the Mac does not know, is not found before any terminal is touched.
        let before = calls.all.count
        #expect(await source.send(sessionId: codex, text: "hello") == .notFound)
        #expect(await source.send(sessionId: "no-such-session", text: "hello") == .notFound)
        #expect(await source.interrupt(sessionId: codex, hard: true) == .notFound)
        #expect(calls.all.count == before)
        #expect(calls.all.first == "send \(session) hello")
        #expect(calls.all.contains("interrupt \(session) true"))

        // The default commands are the shared `TerminalController` functions: a session whose terminal cannot
        // be resolved is `not_found` there, as `mobile.chat.send` reports it.
        let shared = await MainActor.run { ShellXLinkChatSource(service: { service }) }
        #expect(await shared.send(sessionId: session, text: "hello") == .notFound)
        #expect(await shared.interrupt(sessionId: session, hard: false) == .notFound)
        let mobile = await MainActor.run { TerminalController.shared }
        guard case .err(let code, _, _) = await mobile.v2MobileChatSend(params: ["session_id": session, "text": "hello"]) else {
            Issue.record("mobile.chat.send must fail for an unbound session")
            return
        }
        #expect(code == "not_found")
    }

    /// A phone connected over Link (no mobile client subscribed to `chat.message`) still gets live entries:
    /// its frame observer counts as a subscriber, so hook events start the transcript tailer.
    @Test func testFrameObserverKeepsTranscriptTailing() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let service = await MainActor.run { Self.makeService(home: home) }
        let source = await MainActor.run { ShellXLinkChatSource(service: { service }) }
        let unobserved = try await MainActor.run {
            try Self.addSession(service, home: home, lines: [Self.userLine("u-1", "first")]).id
        }
        #expect(await MainActor.run { Self.tailerActive(service, unobserved) } == false)

        let pushes = Pushes()
        let stream = source.entries()
        let consumer = Task { for await push in stream { pushes.record(push) } }
        #expect(await Self.waitUntil { service.frameObserverCount == 1 })
        let (session, transcript) = try await MainActor.run {
            try Self.addSession(service, home: home, lines: [Self.userLine("u-1", "first")])
        }
        #expect(await MainActor.run { Self.tailerActive(service, session) })
        // Waits for the tailer's first read, so the next line arrives as a live append.
        _ = await service.history(sessionID: session, beforeSeq: nil, limit: 1)

        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Self.assistantLine("a-1", [["type": "text", "text": "Done"]]) + "\n").utf8))
        try handle.close()

        #expect(await Self.waitUntil { pushes.entries.contains { $0.text == "Done" } })
        let pushed = try #require(pushes.entries.first { $0.text == "Done" })
        #expect(pushed.role == .agent)
        #expect(pushed.kind == .prose)
        let paged = try #require(await source.history(sessionId: session, beforeSeq: nil, limit: 50)?.entries
            .first { $0.id == pushed.id })
        #expect(paged.rev > pushed.rev)

        consumer.cancel()
        _ = await consumer.value
        #expect(await Self.waitUntil { service.frameObserverCount == 0 })
    }

    /// Claude Code writes a new session's transcript only after its first prompt hook, so SessionStart and the
    /// first UserPromptSubmit name a file (in a project folder) that does not exist yet. A phone connected
    /// before the session started still gets the whole first turn live, not only from the second prompt on.
    @Test func testFirstTurnOfNewSessionIsPushed() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let service = await MainActor.run { Self.makeService(home: home) }
        let source = await MainActor.run { ShellXLinkChatSource(service: { service }) }
        let pushes = Pushes()
        let stream = source.entries()
        let consumer = Task { for await push in stream { pushes.record(push) } }
        defer { consumer.cancel() }
        #expect(await Self.waitUntil { service.frameObserverCount == 1 })
        let session = UUID().uuidString
        let project = home.appendingPathComponent("projects/-private-tmp-first-turn", isDirectory: true)
        let transcript = project.appendingPathComponent("\(session).jsonl")
        func hook(_ name: WorkstreamEvent.HookEventName, tool: String? = nil) -> WorkstreamEvent {
            WorkstreamEvent(sessionId: session, hookEventName: name, source: "claude", transcriptPath: transcript.path,
                            cwd: "/private/tmp/first-turn", toolName: tool)
        }
        func append(_ line: String) throws {
            if !FileManager.default.fileExists(atPath: transcript.path) {
                try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
                try Data().write(to: transcript)
            }
            let handle = try FileHandle(forWritingTo: transcript)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
        }

        await MainActor.run {
            service.noteHookEvent(hook(.sessionStart))
            service.noteHookEvent(hook(.userPromptSubmit))
        }
        try append(Self.userLine("u-1", "Create the file"))
        await MainActor.run { service.noteHookEvent(hook(.preToolUse, tool: "Bash")) }
        try append(Self.assistantLine("a-1", [
            ["type": "tool_use", "id": "t-touch", "name": "Bash", "input": ["command": "touch first.txt"]],
        ]))
        try append(Self.assistantLine("a-2", [["type": "text", "text": "Created first.txt"]]))
        await MainActor.run { service.noteHookEvent(hook(.stop)) }

        #expect(await Self.waitUntil {
            let texts = Set(pushes.entries.map(\.text))
            return texts.isSuperset(of: ["Create the file", "touch first.txt", "Created first.txt"])
        })
        let entries = pushes.entries
        #expect(entries.first { $0.text == "Create the file" }?.role == .user)
        #expect(entries.first { $0.text == "touch first.txt" }?.toolName == "Bash")
        #expect(entries.first { $0.text == "Created first.txt" }?.kind == .prose)
    }

    /// The tailer updates its cache before it publishes the batch, so a history read can return an entry
    /// older than a push that reached the main actor while the read was in flight. The page then carries the
    /// pushed content under a new revision; a stale copy never outranks the push on the phone.
    @Test func testStaleHistoryCopyNeverOutranksAPush() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let service = await MainActor.run { Self.makeService(home: home) }
        let (source, session) = try await MainActor.run { () throws -> (ShellXLinkChatSource, String) in
            (ShellXLinkChatSource(service: { service }), try Self.addSession(service, home: home, lines: []).id)
        }
        let pushes = Pushes()
        let stream = source.entries()
        let consumer = Task { for await push in stream { pushes.record(push) } }
        defer { consumer.cancel() }
        #expect(await Self.waitUntil { service.frameObserverCount == 1 })
        let running = ChatMessage(id: "tool-1", seq: 3, role: .agent, timestamp: Date(timeIntervalSince1970: 1),
                                  kind: .terminal(ChatTerminalCapture(command: "make", isRunning: true)))
        let finished = ChatMessage(id: "tool-1", seq: 3, role: .agent, timestamp: Date(timeIntervalSince1970: 1),
                                   kind: .terminal(ChatTerminalCapture(command: "make && echo ok", isRunning: false)))

        let page = await MainActor.run { () -> [ChatEntry] in
            let read = source.beginHistoryRead(sessionId: session)
            source.receive(ChatSessionEventFrame(sessionID: session, event: .updated([finished])))
            return source.finishHistoryRead(read, page: ChatHistoryPage(messages: [running], hasMore: false)).entries
        }

        #expect(await Self.waitUntil { pushes.entries.contains { $0.id == "tool-1" } })
        let pushed = try #require(pushes.entries.first { $0.id == "tool-1" })
        let paged = try #require(page.first)
        #expect(paged.text == "make && echo ok")
        #expect(paged.rev > pushed.rev)
        #expect(ChatEntry.newer(pushed, paged).text == "make && echo ok")
    }
}
