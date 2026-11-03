public import Foundation

/// Runs one script in the user's login shell (`/bin/zsh -lc <script>`) and returns its output.
///
/// Blocks for up to about `timeout` + 4 s (kill grace and drain join). Call it on a dedicated thread
/// (`Thread.detachNewThread`), never on the main actor or the cooperative pool: the drain needs a pool thread.
public struct ShellXLoginShellCommand: Sendable {
    private let script: String
    private let timeout: Duration

    /// Creates a command that runs `script`, giving the shell `timeout` before killing it.
    public init(script: String, timeout: Duration = .seconds(5)) {
        self.script = script
        self.timeout = timeout
    }

    /// The shell's standard output when it exits 0 within the timeout, else `nil`.
    public func callAsFunction() -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", script]
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // Bounded wait with deadline for a synchronous Process API; signalled once.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
            return nil
        }
        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        let captured = ResultBox()
        // Bounded wait with deadline for a synchronous Process API; signalled once.
        let drained = DispatchSemaphore(value: 0)
        Task.detached {
            let data = outHandle.readDataToEndOfFile()
            _ = errHandle.readDataToEndOfFile()
            captured.data = data
            drained.signal()
        }
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        if exited.wait(timeout: .now() + seconds) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }
        guard !process.isRunning, drained.wait(timeout: .now() + 2) == .success else { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: captured.data, as: UTF8.self)
    }
}

/// `@unchecked Sendable` is safe: `data` is written once before the `drained` signal and read only after a successful join.
private final class ResultBox: @unchecked Sendable {
    var data = Data()
}
