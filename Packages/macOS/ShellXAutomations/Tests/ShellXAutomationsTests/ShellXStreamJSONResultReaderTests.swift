import Foundation
import Testing
@testable import ShellXAutomations

@Suite struct ShellXStreamJSONResultReaderTests {
    private func read(_ name: String) throws -> ShellXClaudeResult {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
        var reader = ShellXStreamJSONResultReader()
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") { reader.ingest(line: String(line)) }
        return reader.result
    }

    @Test func readsSuccess() throws {
        let r = try read("success")
        #expect(r.sessionId == "11111111-2222-3333-4444-555555555555")
        #expect(r.resultText == "Hi! What can I help you with?")
        #expect(!r.isError && r.permissionDenials.isEmpty)
    }

    @Test func readsPermissionDenials() throws {
        let r = try read("permission-denied")
        #expect(r.permissionDenials == ["Bash", "Write", "Bash"])
        #expect(r.resultText == "I could not run the command.")
    }

    @Test func readsError() throws {
        let r = try read("error")
        #expect(r.isError && r.resultText == "Execution failed")
    }

    @Test func noResultEventLeavesTextNil() throws {
        let r = try read("no-result")
        #expect(r.resultText == nil)
        #expect(r.sessionId != nil)
    }

    @Test func ignoresGarbageLines() {
        var reader = ShellXStreamJSONResultReader()
        reader.ingest(line: "not json")
        reader.ingest(line: "[1,2]")
        #expect(reader.result == ShellXClaudeResult())
    }
}
