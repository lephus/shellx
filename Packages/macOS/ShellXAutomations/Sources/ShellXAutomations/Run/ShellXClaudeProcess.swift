public import Foundation

/// Launches the real `claude` binary with `Process`.
public struct ShellXClaudeProcess: ShellXClaudeLaunching {
    private static let stderrTailBytes = 4096

    private let executable: String
    private let environment: [String: String]

    /// Creates a launcher for the binary at `executable` using `environment` (usually the current one).
    public init(executable: String, environment: [String: String], timeLimit: Duration = .seconds(2 * 60 * 60)) {
        self.executable = executable
        self.environment = environment
    }

    /// The argument vector after the executable.
    func arguments(prompt: String, allowedTools: [String], resumeSessionId: String?) -> [String] {
        var args = ["-p", prompt, "--output-format", "stream-json", "--verbose"]
        if !allowedTools.isEmpty { args += ["--allowedTools", allowedTools.joined(separator: ",")] }
        if let resumeSessionId { args += ["--resume", resumeSessionId] }
        return args
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
        let tailBytes = Self.stderrTailBytes
        let outTask = Task.detached { () -> ShellXClaudeResult in
            var reader = ShellXStreamJSONResultReader()
            var pending = Data()
            while true {
                let chunk = outHandle.availableData
                if chunk.isEmpty { break }
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
            while true {
                let chunk = errHandle.availableData
                if chunk.isEmpty { break }
                tail.append(chunk)
                if tail.count > tailBytes { tail = tail.suffix(tailBytes) }
            }
            return String(decoding: tail, as: UTF8.self)
        }

        nonisolated(unsafe) let unsafeProcess = process
        let status: Int32 = try await withTaskCancellationHandler {
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

        var result = await outTask.value
        result.stderrTail = await errTask.value
        result.exitCode = status
        return result
    }
}
