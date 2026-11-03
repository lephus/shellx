public import Foundation

/// A chat with Claude Code that drafts a skill, workflow or cronjob.
///
/// Runs `claude -p` in stream-json mode, turns its output into ``ShellXCreatorEvent`` values and
/// keeps structured `shellx-draft` / `shellx-choices` blocks out of the visible text.
public actor ShellXCreatorSession {
    /// Events for the UI; finishes when the session is cancelled.
    public nonisolated let events: AsyncStream<ShellXCreatorEvent>

    private let continuation: AsyncStream<ShellXCreatorEvent>.Continuation
    private let launcher: any ShellXCreatorProcessLaunching
    private let systemPrompt: String
    private let workingDirectory: URL
    private var writeLine: (@Sendable (String) async throws -> Void)?
    private var stopProcess: (@Sendable () async -> Void)?
    private var readerTask: Task<Void, Never>?
    private var parser = ShellXAssistantBlockParser()
    private var cancelled = false
    /// True while ``start(seed:)`` waits for Claude Code to launch.
    private var starting = false
    /// Messages sent while Claude Code launches, waiting for ``start(seed:)`` to finish.
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a session.
    ///
    /// - Parameters:
    ///   - launcher: Starts Claude Code.
    ///   - systemPrompt: Prompt text; `{{SHELLX_CLI}}` is replaced with `cliPath`.
    ///   - workingDirectory: Scratch directory Claude Code runs in.
    ///   - localeIdentifier: Locale the assistant replies in by default.
    ///   - cliPath: Absolute path of the `shellx` CLI.
    public init(
        launcher: any ShellXCreatorProcessLaunching,
        systemPrompt: String,
        workingDirectory: URL,
        localeIdentifier: String,
        cliPath: String
    ) {
        (events, continuation) = AsyncStream<ShellXCreatorEvent>.makeStream()
        self.launcher = launcher
        self.workingDirectory = workingDirectory
        self.systemPrompt = systemPrompt.replacingOccurrences(of: "{{SHELLX_CLI}}", with: cliPath)
            + "\n\nReply in the language of this locale unless the user writes in another language: \(localeIdentifier)."
    }

    /// Starts Claude Code and, when `seed` is given, sends it as the first message.
    ///
    /// A session cancelled while Claude Code starts stops the new process at once.
    public func start(seed: ShellXCreatorSeed?) async throws {
        guard writeLine == nil, !cancelled else { return }
        starting = true
        defer {
            starting = false
            let waiters = startWaiters
            startWaiters = []
            for waiter in waiters { waiter.resume() }
        }
        let arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json",
            "--include-partial-messages", "--verbose", "--append-system-prompt", systemPrompt,
            "--allowedTools", "Read,Glob,Grep",
            "--disallowedTools", "Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch",
            // A user's `permissions.defaultMode` must not widen the creator, and it needs no MCP servers.
            "--permission-mode", "default", "--strict-mcp-config",
        ]
        let process = try await launcher.start(arguments: arguments, workingDirectory: workingDirectory)
        // `cancel()` may have run while Claude Code was starting; it found nothing to stop.
        guard !cancelled else {
            await process.stop()
            return
        }
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
        if let seed {
            do {
                try await send(seed.firstMessage)
            } catch {
                await cancel()
                throw error
            }
        }
    }

    /// Sends a user message and marks the session busy.
    ///
    /// A message sent while Claude Code is still launching waits for it (after the seed, if any).
    public func send(_ text: String) async throws {
        let encoded = try JSONEncoder().encode(text)
        let json = String(decoding: encoded, as: UTF8.self)
        if writeLine == nil, starting, !cancelled {
            continuation.yield(.busy(true))
            await withCheckedContinuation { startWaiters.append($0) }
        }
        guard let writeLine else {
            continuation.yield(.busy(false))
            throw ShellXCreatorProcess.Failure(message: "The assistant is not running.")
        }
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
            let subtype = object["subtype"] as? String
            if object["is_error"] as? Bool == true || (subtype != nil && subtype != "success") {
                let text = (object["result"] as? String) ?? ""
                continuation.yield(.failed(text.isEmpty ? (subtype ?? "Claude Code reported an error.") : text))
            }
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
