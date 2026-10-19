import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs cmux-tui. argv carries only flags and file paths (tickets and invites travel as files).
public protocol SidecarLaunching: Sendable {
    /// Runs to completion and returns the exit status and stdout.
    func run(_ executable: URL, _ args: [String], env: [String: String]) async throws -> (status: Int32, stdout: Data)
    /// Starts a long-lived process; `onLine` gets each stdout line, `onExit` the exit status (once).
    func launch(_ executable: URL, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) throws -> any SidecarHandle
}

public protocol SidecarHandle: Sendable {
    func terminate()
}

/// Foundation `Process`, never through a shell. The child environment is only `HOME`, `LANG`, `TMPDIR`
/// (inherited when set), `PATH=/usr/bin:/bin` and the keys the caller passes; nothing else is inherited
/// (no `CMUX_*`, no `SSH_AUTH_SOCK`, no `SHELLX_*`). stdin and stderr are `/dev/null`; stdout is
/// never logged.
public struct ShellXSidecarProcess: SidecarLaunching {
    public static let inheritedKeys = ["HOME", "LANG", "TMPDIR"]
    public static let fixedPath = "/usr/bin:/bin"
    /// stdout kept by `run` (status replies are tiny).
    static let runOutputLimit = 1 << 20
    /// Longest line passed to `onLine`; longer lines are dropped.
    static let lineLimit = 1 << 20

    private let baseEnvironment: [String: String]
    private let runTimeout: TimeInterval
    /// `terminate()` sends SIGTERM, then SIGKILL this long after if the process still runs.
    private let killGrace: TimeInterval

    public init(baseEnvironment: [String: String] = ProcessInfo.processInfo.environment, runTimeout: TimeInterval = 30,
                killGrace: TimeInterval = 3) {
        self.baseEnvironment = baseEnvironment
        self.runTimeout = runTimeout
        self.killGrace = killGrace
    }

    public static func scrubbedEnvironment(base: [String: String], extra: [String: String]) -> [String: String] {
        var env: [String: String] = ["PATH": fixedPath]
        for key in inheritedKeys { if let value = base[key] { env[key] = value } }
        for (key, value) in extra { env[key] = value }
        return env
    }

    public func run(_ executable: URL, _ args: [String], env: [String: String]) async throws -> (status: Int32, stdout: Data) {
        let output = OutputCollector(limit: Self.runOutputLimit)
        let timeout = runTimeout
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(status: Int32, stdout: Data), any Error>) in
            do {
                let handle = try spawn(executable, args, env: env, onData: { output.append($0) },
                                       onExit: { cont.resume(returning: (status: $0, stdout: output.data)) })
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { handle.terminate() }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    public func launch(_ executable: URL, _ args: [String], env: [String: String],
                       onLine: @escaping @Sendable (String) -> Void,
                       onExit: @escaping @Sendable (Int32) -> Void) throws -> any SidecarHandle {
        let lines = LineSplitter(limit: Self.lineLimit, onLine: onLine)
        return try spawn(executable, args, env: env, onData: { lines.feed($0) }, onExit: { status in
            lines.finish()
            onExit(status)
        })
    }

    /// Starts the process; stdout is read non-blocking on one serial queue, and the exit callback runs on
    /// that queue after the pipe has been drained, so every byte written before exit is delivered first.
    private func spawn(_ executable: URL, _ args: [String], env: [String: String],
                       onData: @escaping @Sendable (Data) -> Void,
                       onExit: @escaping @Sendable (Int32) -> Void) throws -> SidecarProcessHandle {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = Self.scrubbedEnvironment(base: baseEnvironment, extra: env)
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let reader = PipeReader(pipe: pipe, onData: onData)
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            reader.finish { onExit(status) }
        }
        try process.run()
        reader.start()
        return SidecarProcessHandle(process, killGrace: killGrace)
    }
}

final class SidecarProcessHandle: SidecarHandle, @unchecked Sendable {
    private let process: Process
    private let killGrace: TimeInterval

    init(_ process: Process, killGrace: TimeInterval) {
        self.process = process
        self.killGrace = RemoteTimers.clamp(killGrace)
    }

    /// SIGTERM now, SIGKILL after `killGrace` if it is still running; never blocks the caller.
    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killGrace) { [self] in
            // isRunning turns false when Foundation reaps the child, so a dead process is never
            // signalled; only the instant between reaping and that flag update is left (negligible).
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

/// Reads a pipe's read end non-blocking on a private serial queue.
private final class PipeReader: @unchecked Sendable {
    private let pipe: Pipe
    private let fd: Int32
    private let onData: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "pro.shellx.sidecar.stdout")
    private var source: (any DispatchSourceRead)?
    private var done = false   // queue-confined

    init(pipe: Pipe, onData: @escaping @Sendable (Data) -> Void) {
        self.pipe = pipe
        self.fd = pipe.fileHandleForReading.fileDescriptor
        self.onData = onData
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    func start() {
        queue.async {
            guard !self.done else { return }
            let source = DispatchSource.makeReadSource(fileDescriptor: self.fd, queue: self.queue)
            source.setEventHandler { [weak self] in self?.drain() }
            // Close only after the source is gone, so a reused fd number is never watched.
            let pipe = self.pipe
            source.setCancelHandler { try? pipe.fileHandleForReading.close() }
            self.source = source
            source.resume()
        }
    }

    func finish(_ then: @escaping @Sendable () -> Void) {
        queue.async {
            if !self.done { self.drain() }
            self.stop()
            then()
        }
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while !done {
            let n = buffer.withUnsafeMutableBytes { raw -> Int in
                #if canImport(Darwin)
                Darwin.read(fd, raw.baseAddress!, raw.count)
                #else
                Glibc.read(fd, raw.baseAddress!, raw.count)
                #endif
            }
            if n > 0 { onData(Data(buffer[0..<n])); continue }
            if n < 0 && errno == EINTR { continue }
            if n == 0 { stop() }   // EOF
            return                 // EAGAIN: wait for the next event
        }
    }

    private func stop() {
        guard !done else { return }
        done = true
        if let source {
            source.cancel()
            self.source = nil
        } else {
            try? pipe.fileHandleForReading.close()
        }
    }
}

/// Splits stdout into lines (LF, optional CR); drops lines longer than `limit`.
private final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()
    private var discarding = false
    private let limit: Int
    private let onLine: @Sendable (String) -> Void

    init(limit: Int, onLine: @escaping @Sendable (String) -> Void) { self.limit = limit; self.onLine = onLine }

    /// Called only from the reader's serial queue.
    func feed(_ data: Data) {
        var rest = data[...]
        while let newline = rest.firstIndex(of: 0x0A) {
            if !discarding { buffer.append(rest[rest.startIndex..<newline]); emit() }
            buffer.removeAll(keepingCapacity: true)
            discarding = false
            rest = rest[rest.index(after: newline)...]
        }
        guard !discarding else { return }
        buffer.append(rest)
        if buffer.count > limit { buffer.removeAll(); discarding = true }
    }

    func finish() {
        if !discarding && !buffer.isEmpty { emit() }
        buffer.removeAll()
    }

    private func emit() {
        var line = buffer
        if line.last == 0x0D { line.removeLast() }
        onLine(String(decoding: line, as: UTF8.self))
    }
}

/// Collects stdout for `run`, up to a limit.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private let limit: Int
    init(limit: Int) { self.limit = limit }
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if bytes.count < limit { bytes.append(data.prefix(limit - bytes.count)) }
    }
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
}
