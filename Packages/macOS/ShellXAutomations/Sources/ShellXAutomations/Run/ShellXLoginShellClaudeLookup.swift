public import Foundation

/// Asks the user's login shell where `claude` lives (`/bin/zsh -lc 'command -v claude'`).
public struct ShellXLoginShellClaudeLookup: Sendable {
    private let timeout: Duration

    /// Creates a lookup that gives the shell `timeout` before killing it.
    public init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    /// The absolute path printed by the shell, or `nil`.
    public func callAsFunction() -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        let outTask = Task.detached { outHandle.readDataToEndOfFile() }
        let errTask = Task.detached { errHandle.readDataToEndOfFile() }
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        if finished.wait(timeout: .now() + seconds) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        // Drain via semaphore-free blocking waits on detached tasks.
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.data = await outTask.value
            _ = await errTask.value
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
        guard !process.isRunning, process.terminationStatus == 0 else { return nil }
        return Self.absolutePath(fromOutput: String(decoding: box.data, as: UTF8.self))
    }

    /// The last non-empty line of `output`, if it is an absolute path.
    static func absolutePath(fromOutput output: String) -> String? {
        let last = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        guard let last, last.hasPrefix("/") else { return nil }
        return last
    }
}

private final class ResultBox: @unchecked Sendable {
    var data = Data()
}
