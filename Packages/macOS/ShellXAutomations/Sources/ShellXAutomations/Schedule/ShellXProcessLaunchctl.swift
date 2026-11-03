public import Foundation

/// Runs the real `/bin/launchctl`.
public struct ShellXProcessLaunchctl: ShellXLaunchctlRunning {
    /// Creates the runner.
    public init() {}

    public func run(_ arguments: [String]) async throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let reader = Task.detached { () -> Data in
            (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                try? pipe.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }
        let data = await reader.value
        return (status, String(decoding: data, as: UTF8.self))
    }
}
