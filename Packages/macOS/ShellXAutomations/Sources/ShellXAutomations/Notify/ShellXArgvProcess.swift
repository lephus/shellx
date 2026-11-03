public import Foundation

/// Runs an argument vector (absolute executable first) and returns its exit status. Output is discarded.
public struct ShellXArgvProcess: Sendable {
    /// Creates the runner.
    public init() {}

    /// Runs `argv` and waits for it to exit.
    public func run(_ argv: [String]) async throws -> Int32 {
        guard let executable = argv.first else { throw CocoaError(.fileNoSuchFile) }
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = Array(argv.dropFirst())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
