public import Foundation

/// A chat with Claude Code that drafts a skill, workflow or cronjob.
///
/// Runs `claude -p` in stream-json mode, turns its output into ``ShellXCreatorEvent`` values and
/// keeps structured `shellx-draft` / `shellx-choices` blocks out of the visible text.
public actor ShellXCreatorSession {
    /// Events for the UI; finishes when the session is cancelled.
    public nonisolated let events: AsyncStream<ShellXCreatorEvent>
    /// Path of the `claude` executable the launcher was built for.
    public nonisolated let claudePath: String

    private let continuation: AsyncStream<ShellXCreatorEvent>.Continuation
    private let launcher: any ShellXCreatorProcessLaunching
    private let systemPrompt: String
    private let workingDirectory: URL
    private var writeLine: (@Sendable (String) async throws -> Void)?
    private var stopProcess: (@Sendable () async -> Void)?
    private var readerTask: Task<Void, Never>?
    private var parser = ShellXAssistantBlockParser()
    private var cancelled = false

    /// Creates a session.
    ///
    /// - Parameters:
    ///   - launcher: Starts Claude Code.
    ///   - claudePath: Path of the `claude` executable.
    ///   - systemPrompt: Prompt text; `{{SHELLX_CLI}}` is replaced with `cliPath`.
    ///   - workingDirectory: Scratch directory Claude Code runs in.
    ///   - localeIdentifier: Locale the assistant replies in by default.
    ///   - cliPath: Absolute path of the `shellx` CLI.
    public init(
        launcher: any ShellXCreatorProcessLaunching,
        claudePath: String,
        systemPrompt: String,
        workingDirectory: URL,
        localeIdentifier: String,
        cliPath: String
    ) {
        (events, continuation) = AsyncStream<ShellXCreatorEvent>.makeStream()
        self.launcher = launcher
        self.claudePath = claudePath
        self.workingDirectory = workingDirectory
        self.systemPrompt = systemPrompt.replacingOccurrences(of: "{{SHELLX_CLI}}", with: cliPath)
            + "\n\nReply in the language of this locale unless the user writes in another language: \(localeIdentifier)."
    }

    /// Starts Claude Code and, when `seed` is given, sends it as the first message.
    public func start(seed: ShellXCreatorSeed?) async throws {
        guard writeLine == nil, !cancelled else { return }
        let arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json",
            "--include-partial-messages", "--verbose", "--append-system-prompt", systemPrompt,
            "--allowedTools", "Read,Glob,Grep",
            "--disallowedTools", "Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch",
        ]
        let process = try await launcher.start(arguments: arguments, workingDirectory: workingDirectory)
        writeLine = process.send
        stopProcess = process.stop
        let lines = process.lines
        readerTask = Task { [weak self] in
            do {
                for try await line in lines { await self?.handle(line: line) }
                await self?.processEnded(error: nil)
            } catch {
                await self?.processEnded(error: error)
            }
        }
        if let seed { try await send(seed.firstMessage) }
    }

    /// Sends a user message and marks the session busy.
    public func send(_ text: String) async throws {
        guard let writeLine else { throw ShellXCreatorProcess.Failure(message: "The assistant is not running.") }
        let encoded = try JSONEncoder().encode(text)
        let json = String(decoding: encoded, as: UTF8.self)
        continuation.yield(.busy(true))
        do {
            try await writeLine(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":\#(json)}]}}"#)
        } catch {
            continuation.yield(.failed(error.localizedDescription))
            continuation.yield(.busy(false))
            throw error
        }
    }

    /// Stops Claude Code and finishes `events`.
    public func cancel() async {
        cancelled = true
        readerTask?.cancel()
        readerTask = nil
        writeLine = nil
        let stop = stopProcess
        stopProcess = nil
        await stop?()
        continuation.finish()
    }

    private func handle(line: String) {
        guard !cancelled,
              let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return }
            let visible = parser.ingest(delta: text)
            if !visible.isEmpty { continuation.yield(.textDelta(visible)) }
        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }
            let full = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
            parser = ShellXAssistantBlockParser()
            guard !full.isEmpty else { return }
            let result = parser.finish(fullText: full)
            if let draft = result.draft { continuation.yield(.draft(draft)) }
            continuation.yield(.assistantMessage(text: result.visible, choices: result.choices))
        case "result":
            parser = ShellXAssistantBlockParser()
            continuation.yield(.busy(false))
        default:
            break
        }
    }

    private func processEnded(error: (any Error)?) {
        guard !cancelled else { return }
        let message = error?.localizedDescription ?? "Claude Code stopped unexpectedly."
        continuation.yield(.failed(message.isEmpty ? "Claude Code stopped unexpectedly." : message))
        continuation.yield(.busy(false))
        writeLine = nil
    }
}
