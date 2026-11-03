import Foundation
import Testing
@testable import ShellXAutomations

@Suite struct ShellXClaudeProcessTests {
    @Test func argumentsOmitEmptyAllowedTools() {
        let p = ShellXClaudeProcess(executable: "/x", environment: [:])
        #expect(p.arguments(prompt: "hi", allowedTools: [], resumeSessionId: nil)
            == ["-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "default", "--", "hi"])
        #expect(p.arguments(prompt: "hi", allowedTools: ["Read", "Grep"], resumeSessionId: "s1")
            == ["-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "default",
                "--allowedTools", "Read,Grep", "--resume", "s1", "--", "hi"])
    }

    /// A user's `permissions.defaultMode` (bypassPermissions, acceptEdits) must never widen an unattended run,
    /// and a prompt that starts with `-` must stay the prompt.
    @Test func argumentsPinDefaultPermissionModeAndEndOptionsBeforePrompt() {
        let args = ShellXClaudeProcess(executable: "/x", environment: [:])
            .arguments(prompt: "--dangerously-skip-permissions do it", allowedTools: ["Read"], resumeSessionId: nil)
        #expect(args.firstIndex(of: "--permission-mode").map { args[$0 + 1] } == "default")
        #expect(Array(args.suffix(2)) == ["--", "--dangerously-skip-permissions do it"])
        #expect(args.filter { $0 == "--dangerously-skip-permissions do it" }.count == 1)
    }

    /// A `claude` that leaves a background child holding stdout open must not hang the run:
    /// output is drained for at most 5 s after claude exits.
    @Test func backgroundChildHoldingStdoutDoesNotHangTheRun() async throws {
        let dir = try Self.scratch()
        let pidFile = dir.appending(path: "bg.pid")
        let script = try Self.script(in: dir, """
        #!/bin/sh
        sleep 30 &
        echo $! > '\(pidFile.path)'
        printf '{"type":"result","is_error":false,"result":"hi","session_id":"s"}\n'
        exit 0
        """)
        defer {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGKILL)
            }
        }
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await ShellXClaudeProcess(executable: script.path, environment: ProcessInfo.processInfo.environment)
            .run(prompt: "p", workingDirectory: dir, allowedTools: [], resumeSessionId: nil, transcript: dir.appending(path: "out.jsonl"))
        let elapsed = clock.now - started
        #expect(elapsed < .seconds(9), "took \(elapsed)")
        #expect(result.exitCode == 0)
        #expect(result.resultText == "hi")
    }

    /// A run that outlives its time limit is stopped and fails with the time-limit reason.
    @Test func runPastTheTimeLimitFails() async throws {
        let dir = try Self.scratch()
        let script = try Self.script(in: dir, "#!/bin/sh\nexec sleep 30\n")
        let clock = ContinuousClock()
        let started = clock.now
        await #expect {
            _ = try await ShellXClaudeProcess(executable: script.path, environment: ProcessInfo.processInfo.environment, timeLimit: .seconds(1))
                .run(prompt: "p", workingDirectory: dir, allowedTools: [], resumeSessionId: nil, transcript: dir.appending(path: "out.jsonl"))
        } throws: { error in
            error.localizedDescription == "Claude Code ran longer than the time limit."
        }
        #expect(clock.now - started < .seconds(5))
    }

    /// A claude that ignores SIGTERM is killed 5 s after the time limit.
    @Test func runIgnoringTerminateIsKilled() async throws {
        let dir = try Self.scratch()
        let script = try Self.script(in: dir, "#!/bin/sh\ntrap '' TERM\nexec sleep 30\n")
        let clock = ContinuousClock()
        let started = clock.now
        await #expect {
            _ = try await ShellXClaudeProcess(executable: script.path, environment: ProcessInfo.processInfo.environment, timeLimit: .seconds(1))
                .run(prompt: "p", workingDirectory: dir, allowedTools: [], resumeSessionId: nil, transcript: dir.appending(path: "out.jsonl"))
        } throws: { error in
            error.localizedDescription == "Claude Code ran longer than the time limit."
        }
        let elapsed = clock.now - started
        #expect(elapsed >= .seconds(5) && elapsed < .seconds(10), "took \(elapsed)")
    }

    private static func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "proc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func script(in dir: URL, _ text: String) throws -> URL {
        let script = dir.appending(path: "fake-claude")
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
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
