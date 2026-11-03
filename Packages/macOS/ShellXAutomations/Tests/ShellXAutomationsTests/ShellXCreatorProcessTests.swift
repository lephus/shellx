import Foundation
import Testing
@testable import ShellXAutomations

struct ShellXCreatorProcessTests {
    @Test func echoesLinesAndStops() async throws {
        let launcher = ShellXCreatorProcess(executablePath: "/bin/cat", environment: [:])
        let process = try await launcher.start(arguments: [], workingDirectory: URL(filePath: "/tmp"))
        try await process.send("hello")
        var iterator = process.lines.makeAsyncIterator()
        #expect(try await iterator.next() == "hello")
        await process.stop()
    }

    @Test func missingExecutableThrows() async {
        let launcher = ShellXCreatorProcess(executablePath: "/nonexistent/claude", environment: [:])
        await #expect(throws: ShellXCreatorProcess.Failure.self) {
            _ = try await launcher.start(arguments: [], workingDirectory: URL(filePath: "/tmp"))
        }
    }
}
