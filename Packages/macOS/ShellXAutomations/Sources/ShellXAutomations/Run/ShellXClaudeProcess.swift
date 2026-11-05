public import Foundation

/// Launches the real `claude` binary with `Process`.
///
/// A run is always bounded. It is stopped after its time limit (SIGTERM, then SIGKILL five seconds later) and
/// fails with ``ShellXClaudeTimeLimitError``. Once `claude` exits, its output is read for at most five more
/// seconds, so a background child that inherited standard output cannot keep the run open.
public struct ShellXClaudeProcess: ShellXClaudeLaunching {
    /// How long one invocation may run by default: two hours.
    public static let defaultTimeLimit: Duration = .seconds(2 * 60 * 60)

    private static let stderrTailBytes = 4096
    private static let drainLimit: Duration = .seconds(5)
    private static let killGrace: Duration = .seconds(5)

    private let executable: String
    private let environment: [String: String]
    /// How long one invocation may run before it is stopped and fails.
    let timeLimit: Duration
    private let toolAccess: ShellXClaudeToolAccess

    /// Creates a launcher for the binary at `executable` using `environment` (usually the current one).
    ///
    /// - Parameters:
    ///   - timeLimit: How long one invocation may run before it is stopped and fails.
    ///   - toolAccess: Which tools Claude may use; automation runs keep the default, ``ShellXClaudeToolAccess/granted``.
    public init(
        executable: String,
        environment: [String: String],
        timeLimit: Duration = Self.defaultTimeLimit,
        toolAccess: ShellXClaudeToolAccess = .granted
    ) {
        self.executable = executable
        self.environment = environment
        self.timeLimit = timeLimit
        self.toolAccess = toolAccess
    }

    /// The argument vector after the executable.
    ///
    /// `--permission-mode default` keeps a user's `permissions.defaultMode` (such as `bypassPermissions` or
    /// `acceptEdits`) from widening an unattended run. With ``ShellXClaudeToolAccess/none``, `--tools ""` turns
    /// every tool off, `--strict-mcp-config` skips the user's MCP servers, `--disallowedTools` stays as a
    /// fallback and `--no-session-persistence` keeps the call out of the user's sessions. `--` ends the
    /// options, so a prompt that starts with `-` stays the prompt.
    func arguments(prompt: String, allowedTools: [String], resumeSessionId: String?) -> [String] {
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "default"]
        if toolAccess == .none {
            args += [
                "--tools", "", "--strict-mcp-config",
                "--disallowedTools", ShellXClaudeToolAccess.writingAndNetworkTools,
                "--no-session-persistence",
            ]
        }
        if !allowedTools.isEmpty { args += ["--allowedTools", allowedTools.joined(separator: ",")] }
        if let resumeSessionId { args += ["--resume", resumeSessionId] }
        return args + ["--", prompt]
    }

    public func run(
        prompt: String,
        workingDirectory: URL,
        allowedTools: [String],
        resumeSessionId: String?,
        transcript: URL
    ) async throws -> ShellXClaudeResult {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: transcript.path) {
            fileManager.createFile(atPath: transcript.path, contents: nil)
        }
        let transcriptHandle = try FileHandle(forWritingTo: transcript)
        defer { try? transcriptHandle.close() }
        try transcriptHandle.seekToEnd()

        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments(prompt: prompt, allowedTools: allowedTools, resumeSessionId: resumeSessionId)
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        let outChunks = Self.chunks(of: outHandle)
        let errChunks = Self.chunks(of: errHandle)
        defer {
            try? outHandle.close()
            try? errHandle.close()
        }
        let tailBytes = Self.stderrTailBytes
        let outTask = Task.detached { () -> ShellXClaudeResult in
            var reader = ShellXStreamJSONResultReader()
            var pending = Data()
            for await chunk in outChunks {
                try? transcriptHandle.write(contentsOf: chunk)
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let lineData = pending[pending.startIndex..<newline]
                    pending.removeSubrange(pending.startIndex...newline)
                    reader.ingest(line: String(decoding: lineData, as: UTF8.self))
                }
            }
            if !pending.isEmpty { reader.ingest(line: String(decoding: pending, as: UTF8.self)) }
            return reader.result
        }
        let errTask = Task.detached { () -> String in
            var tail = Data()
            for await chunk in errChunks {
                tail.append(chunk)
                if tail.count > tailBytes { tail = tail.suffix(tailBytes) }
            }
            return String(decoding: tail, as: UTF8.self)
        }

        nonisolated(unsafe) let unsafeProcess = process
        let limit = timeLimit
        let grace = Self.killGrace
        // Carve-out: a cancellable deadline that is the intended behavior; cancelled as soon as claude exits.
        let deadline = Task.detached { () -> Bool in
            do { try await Task.sleep(for: limit) } catch { return false }
            guard unsafeProcess.isRunning else { return false }
            unsafeProcess.terminate()
            let target = unsafeProcess.processIdentifier
            do { try await Task.sleep(for: grace) } catch { return true }
            if unsafeProcess.isRunning { kill(target, SIGKILL) }
            return true
        }

        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
                    unsafeProcess.terminationHandler = { finished in
                        continuation.resume(returning: finished.terminationStatus)
                    }
                    do {
                        try unsafeProcess.run()
                    } catch {
                        unsafeProcess.terminationHandler = nil
                        try? outPipe.fileHandleForWriting.close()
                        try? errPipe.fileHandleForWriting.close()
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                guard unsafeProcess.isRunning else { return }
                unsafeProcess.terminate()
                let target = unsafeProcess.processIdentifier
                // Bounded (2 s) and deliberately uncancellable: the kill must still happen after the caller is cancelled.
                Task.detached {
                    try? await Task.sleep(for: .seconds(2))
                    if unsafeProcess.isRunning { kill(target, SIGKILL) }
                }
            }
        } catch {
            deadline.cancel()
            outTask.cancel()
            errTask.cancel()
            throw error
        }
        deadline.cancel()
        let timedOut = await deadline.value

        let drainLimit = Self.drainLimit
        // Carve-out: a cancellable deadline for reading what is left; a background child may hold the pipes open.
        let drain = Task.detached {
            do { try await Task.sleep(for: drainLimit) } catch { return }
            outTask.cancel()
            errTask.cancel()
        }
        var result = await outTask.value
        result.stderrTail = await errTask.value
        drain.cancel()
        if timedOut { throw ShellXClaudeTimeLimitError() }
        result.exitCode = status
        return result
    }

    /// The data read from `handle` until end of file, or until the consuming task is cancelled.
    private static func chunks(of handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { readable in
                let chunk = readable.availableData
                if chunk.isEmpty {
                    readable.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }
}
