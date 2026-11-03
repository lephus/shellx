import Foundation
import Testing
@testable import ShellXAutomations

@Suite struct ShellXClaudeProcessTests {
    @Test func argumentsOmitEmptyAllowedTools() {
        let p = ShellXClaudeProcess(executable: "/x", environment: [:])
        #expect(p.arguments(prompt: "hi", allowedTools: [], resumeSessionId: nil) == ["-p", "hi", "--output-format", "stream-json", "--verbose"])
        #expect(p.arguments(prompt: "hi", allowedTools: ["Read", "Grep"], resumeSessionId: "s1")
            == ["-p", "hi", "--output-format", "stream-json", "--verbose", "--allowedTools", "Read,Grep", "--resume", "s1"])
    }

    @Test func capturesTranscriptStderrAndExitCode() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "proc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appending(path: "fake-claude")
        try """
        #!/bin/sh
        echo '{"type":"system","subtype":"init","session_id":"abc"}'
        echo 'oops on stderr' 1>&2
        echo '{"type":"assistant"}'
        printf '{"type":"result","is_error":false,"result":"hello","session_id":"abc","permission_denials":[]}'
        exit 3
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let transcript = dir.appending(path: "output.jsonl")
        let result = try await ShellXClaudeProcess(executable: script.path, environment: ProcessInfo.processInfo.environment)
            .run(prompt: "p", workingDirectory: dir, allowedTools: [], resumeSessionId: nil, transcript: transcript)
        #expect(result.exitCode == 3)
        #expect(result.sessionId == "abc" && result.resultText == "hello")
        #expect(result.stderrTail.contains("oops on stderr"))
        let lines = try String(contentsOf: transcript, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 3)
    }
}
