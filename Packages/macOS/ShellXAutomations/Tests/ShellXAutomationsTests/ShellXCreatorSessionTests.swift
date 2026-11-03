import Foundation
import Testing
@testable import ShellXAutomations

private actor FakeSentLines {
    private(set) var lines: [String] = []
    private(set) var stopped = false
    func add(_ line: String) { lines.append(line) }
    func markStopped() { stopped = true }
}

private final class FakeLauncher: ShellXCreatorProcessLaunching {
    let sent = FakeSentLines()
    let continuation: AsyncThrowingStream<String, any Error>.Continuation
    let lines: AsyncThrowingStream<String, any Error>
    let capturedArguments = FakeSentLines()

    init() {
        (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
    }

    func start(arguments: [String], workingDirectory: URL) async throws -> (
        lines: AsyncThrowingStream<String, any Error>,
        send: @Sendable (String) async throws -> Void,
        stop: @Sendable () async -> Void
    ) {
        await capturedArguments.add(arguments.joined(separator: "\u{1F}"))
        let sent = self.sent
        return (lines, { line in await sent.add(line) }, { await sent.markStopped() })
    }
}

/// A launcher whose `start` waits until the test opens the gate.
private final class GatedLauncher: ShellXCreatorProcessLaunching {
    let sent = FakeSentLines()
    private let gate: AsyncStream<Void>
    let open: AsyncStream<Void>.Continuation
    let started = FakeSentLines()

    init() {
        (gate, open) = AsyncStream<Void>.makeStream()
    }

    func start(arguments: [String], workingDirectory: URL) async throws -> (
        lines: AsyncThrowingStream<String, any Error>,
        send: @Sendable (String) async throws -> Void,
        stop: @Sendable () async -> Void
    ) {
        await started.add("start")
        for await _ in gate {}
        let sent = self.sent
        let (lines, _) = AsyncThrowingStream<String, any Error>.makeStream()
        return (lines, { line in await sent.add(line) }, { await sent.markStopped() })
    }
}

struct ShellXCreatorSessionTests {
    @Test func cancelDuringStartStopsTheProcess() async throws {
        let launcher = GatedLauncher()
        let session = ShellXCreatorSession(
            launcher: launcher, systemPrompt: "p", workingDirectory: URL(filePath: "/tmp"),
            localeIdentifier: "en", cliPath: "/cli"
        )
        let starting = Task { try await session.start(seed: nil) }
        while await launcher.started.lines.isEmpty { await Task.yield() }

        await session.cancel()
        launcher.open.finish()
        try await starting.value

        #expect(await launcher.sent.stopped)
        await #expect(throws: (any Error).self) { try await session.send("hi") }
    }

    private func makeSession(_ launcher: FakeLauncher) -> ShellXCreatorSession {
        ShellXCreatorSession(
            launcher: launcher,
            systemPrompt: "Use {{SHELLX_CLI}} now.",
            workingDirectory: URL(filePath: "/tmp"),
            localeIdentifier: "vi_VN",
            cliPath: "/Applications/ShellX.app/shellx"
        )
    }

    private func collect(_ session: ShellXCreatorSession, until stop: @escaping @Sendable (ShellXCreatorEvent) -> Bool) async -> [ShellXCreatorEvent] {
        var out: [ShellXCreatorEvent] = []
        for await event in session.events {
            out.append(event)
            if stop(event) { break }
        }
        return out
    }

    private let draftJSON = #"{"kind":"skill","name":"pr-digest","description":"d","skillMarkdown":"s"}"#

    @Test func replaysFixtureStream() async throws {
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        try await session.start(seed: nil)
        try await session.send("hi")
        let full = "Sure.\\n```shellx-draft\\n" + draftJSON.replacingOccurrences(of: "\"", with: "\\\"") + "\\n```\\n```shellx-choices\\n{\\\"question\\\":\\\"Q\\\",\\\"multi\\\":false,\\\"options\\\":[\\\"A\\\"]}\\n```"
        launcher.continuation.yield(#"{"type":"system","subtype":"init","session_id":"abc"}"#)
        launcher.continuation.yield(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Sure.\n"}}}"#)
        launcher.continuation.yield(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"```shellx-draft\n"}}}"#)
        launcher.continuation.yield(#"{"type":"weird"}"#)
        launcher.continuation.yield(#"{"type":"assistant","message":{"content":[{"type":"text","text":""# + full + #""}]}}"#)
        launcher.continuation.yield(#"{"type":"result","subtype":"success"}"#)
        let events = await collect(session) { $0 == .busy(false) }
        let draft = ShellXAutomationDraft(kind: .skill, name: "pr-digest", description: "d", notify: ShellXNotifySettings(on: [], targets: []), skillMarkdown: "s")
        #expect(events == [
            .busy(true),
            .textDelta("Sure.\n"),
            .draft(draft),
            .assistantMessage(text: "Sure.", choices: ShellXCreatorChoices(question: "Q", multi: false, options: ["A"])),
            .busy(false),
        ])
    }

    @Test func sendWritesStreamJSONUserLine() async throws {
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        try await session.start(seed: nil)
        try await session.send("hello \"you\"")
        let lines = await launcher.sent.lines
        #expect(lines == [#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello \"you\""}]}}"#])
    }

    @Test func startPassesArgumentsWithPromptSubstitution() async throws {
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        try await session.start(seed: nil)
        let args = await launcher.capturedArguments.lines[0].split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        #expect(Array(args.prefix(8)) == ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--include-partial-messages", "--verbose", "--append-system-prompt"])
        #expect(args[8].hasPrefix("Use /Applications/ShellX.app/shellx now."))
        #expect(args[8].hasSuffix("Reply in the language of this locale unless the user writes in another language: vi_VN."))
        #expect(Array(args.suffix(7)) == [
            "--allowedTools", "Read,Glob,Grep", "--disallowedTools", "Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch",
            "--permission-mode", "default", "--strict-mcp-config",
        ])
    }

    @Test func seedFirstMessageContainsFiles() async throws {
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        let automation = ShellXAutomation(
            id: "id1", kind: .cronjob, name: "nightly", description: "desc",
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
            directory: URL(filePath: "/tmp/x")
        )
        try await session.start(seed: ShellXCreatorSeed(automation: automation, skillMarkdown: "# Body text"))
        let lines = await launcher.sent.lines
        #expect(lines.count == 1)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        let message = try #require(object["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        #expect(text.hasPrefix("Edit this existing cronjob named nightly."))
        #expect(text.contains("automation.json"))
        #expect(text.contains("\"name\" : \"nightly\""))
        #expect(text.contains("SKILL.md"))
        #expect(text.contains("# Body text"))
    }

    @Test func processExitBecomesFailed() async throws {
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        try await session.start(seed: nil)
        try await session.send("hi")
        launcher.continuation.finish()
        let events = await collect(session) { $0 == .busy(false) }
        #expect(events.count == 3)
        #expect(events[0] == .busy(true))
        if case .failed(let message) = events[1] { #expect(!message.isEmpty) } else { Issue.record("expected failed") }
    }

    @Test func streamErrorBecomesFailedWithMessage() async throws {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        try await session.start(seed: nil)
        launcher.continuation.finish(throwing: Boom())
        let events = await collect(session) { $0 == .busy(false) }
        #expect(events == [.failed("boom"), .busy(false)])
    }

    @Test func cancelStopsProcessAndFinishesEvents() async throws {
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        try await session.start(seed: nil)
        await session.cancel()
        #expect(await launcher.sent.stopped)
        var count = 0
        for await _ in session.events { count += 1 }
        #expect(count == 0)
    }

    @Test func errorResultBecomesFailedBeforeIdle() async throws {
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        try await session.start(seed: nil)
        launcher.continuation.yield(#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in"}"#)
        let events = await collect(session) { $0 == .busy(false) }
        #expect(events == [.failed("Not logged in"), .busy(false)])
    }

    @Test func errorSubtypeResultBecomesFailed() async throws {
        let launcher = FakeLauncher()
        let session = makeSession(launcher)
        try await session.start(seed: nil)
        launcher.continuation.yield(#"{"type":"result","subtype":"error_max_turns"}"#)
        let events = await collect(session) { $0 == .busy(false) }
        #expect(events == [.failed("error_max_turns"), .busy(false)])
    }

    @Test func seedFenceOutgrowsBackticksInContent() throws {
        let automation = ShellXAutomation(
            id: "i", kind: .skill, name: "n", description: "d",
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
            directory: URL(filePath: "/tmp")
        )
        let text = ShellXCreatorSeed(automation: automation, skillMarkdown: "a\n```bash\nls\n```\n").firstMessage
        #expect(text.contains("````markdown\n"))
    }
}
