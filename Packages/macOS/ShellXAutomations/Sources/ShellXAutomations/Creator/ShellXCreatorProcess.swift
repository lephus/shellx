public import Foundation

/// Launches the real `claude` executable with Foundation `Process`.
public struct ShellXCreatorProcess: ShellXCreatorProcessLaunching {
    /// A failure to run Claude Code.
    public struct Failure: Error, LocalizedError, Equatable {
        /// What went wrong, including the tail of stderr when there was one.
        public let message: String
        public var errorDescription: String? { message }
    }

    private let executableURL: URL
    private let environment: [String: String]

    /// Creates a launcher for the `claude` executable at `executablePath`.
    public init(executablePath: String, environment: [String: String]) {
        self.executableURL = URL(filePath: executablePath)
        self.environment = environment
    }

    public func start(arguments: [String], workingDirectory: URL) async throws -> (
        lines: AsyncThrowingStream<String, any Error>,
        send: @Sendable (String) async throws -> Void,
        stop: @Sendable () async -> Void
    ) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let (exits, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        do {
            try process.run()
        } catch {
            throw Failure(message: "Could not start Claude Code at \(executableURL.path): \(error.localizedDescription)")
        }
        let stdoutReader = stdout.fileHandleForReading
        let stderrReader = stderr.fileHandleForReading
        let stdinWriter = stdin.fileHandleForWriting

        let lines = AsyncThrowingStream<String, any Error> { continuation in
            let errorTail = Task.detached { () -> String in
                var tail = ""
                Self.readLines(from: stderrReader) { tail = String((tail + $0 + "\n").suffix(2000)) }
                return tail
            }
            let reader = Task.detached {
                Self.readLines(from: stdoutReader) { continuation.yield($0) }
                var status: Int32 = 0
                for await code in exits { status = code }
                let tail = await errorTail.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if status != 0 {
                    continuation.finish(throwing: Failure(message: tail.isEmpty ? "Claude Code exited with status \(status)." : tail))
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }

        let send: @Sendable (String) async throws -> Void = { line in
            guard process.isRunning else { throw Failure(message: "Claude Code is not running.") }
            try stdinWriter.write(contentsOf: Data((line + "\n").utf8))
        }
        let stop: @Sendable () async -> Void = {
            try? stdinWriter.close()
            if process.isRunning { process.terminate() }
            let waiter = Task.detached { process.waitUntilExit() }
            let killer = Task {
                try await Task.sleep(for: .seconds(2))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            await waiter.value
            killer.cancel()
        }
        return (lines, send, stop)
    }

    /// Blocks the calling (detached) task, reading `handle` until EOF and calling `emit` per line.
    private static func readLines(from handle: FileHandle, emit: (String) -> Void) {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                emit(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
        }
        if !buffer.isEmpty { emit(String(decoding: buffer, as: UTF8.self)) }
    }
}
