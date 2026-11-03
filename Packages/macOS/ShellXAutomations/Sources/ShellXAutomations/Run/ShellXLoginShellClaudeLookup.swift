public import Foundation

/// Asks the user's login shell where `claude` lives (`/bin/zsh -lc 'command -v claude'`).
///
/// Blocks for up to about 9 s (timeout, kill grace and drain join). Call it off the main actor and off the
/// cooperative pool: from the CLI's top level before async work starts, or inside `Task.detached` in the app.
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
        return Self.absolutePath(fromOutput: String(decoding: captured.data, as: UTF8.self))
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

/// `@unchecked Sendable` is safe: `data` is written once before the `drained` signal and read only after a successful join.
private final class ResultBox: @unchecked Sendable {
    var data = Data()
}
