import Foundation
import Testing
@testable import ShellXAutomations

@Suite struct ShellXRoutineClaudeEnvironmentTests {
    private let home = URL(filePath: "/Users/test")

    private func environment(
        inherited: [String: String],
        loginShellPath: String?,
        resolved: [String: String] = [:]
    ) -> ShellXRoutineClaudeEnvironment {
        ShellXRoutineClaudeEnvironment(
            inherited: inherited,
            home: home,
            loginShellPath: { loginShellPath },
            resolveSymlinks: { resolved[$0] ?? $0 }
        )
    }

    @Test func claudeFoldersThenLoginShellThenFallbacks() {
        let env = environment(
            inherited: ["PATH": "/usr/bin:/bin", "HOME": "/Users/test", "FOO": "bar"],
            loginShellPath: "Welcome!\n/opt/homebrew/bin:/Users/test/.nvm/bin:/usr/bin:relative/bin::\n\n",
            resolved: ["/Users/test/.npm/bin/claude": "/Users/test/.npm/lib/claude/cli.js"]
        ).environment(forClaudeAt: "/Users/test/.npm/bin/claude")
        #expect(env["PATH"] == [
            "/Users/test/.npm/bin",
            "/Users/test/.npm/lib/claude",
            "/opt/homebrew/bin",
            "/Users/test/.nvm/bin",
            "/usr/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/Users/test/.local/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":"))
        #expect(env["FOO"] == "bar")
        #expect(env["HOME"] == "/Users/test")
    }

    @Test func withoutLoginShellKeepsFallbacksAndInheritedExtras() {
        let env = environment(
            inherited: ["PATH": "/custom/bin:/usr/bin"],
            loginShellPath: nil
        ).environment(forClaudeAt: "/opt/homebrew/bin/claude")
        #expect(env["PATH"] == [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/Users/test/.local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/custom/bin",
        ].joined(separator: ":"))
    }

    @Test func loginShellPathIsItsLastNonEmptyLine() {
        #expect(ShellXRoutineClaudeEnvironment.entries(fromLoginShellOutput: "motd\n/a:/b\n") == ["/a", "/b"])
        #expect(ShellXRoutineClaudeEnvironment.entries(fromLoginShellOutput: "/a:./b:~/c:/d") == ["/a", "/d"])
        #expect(ShellXRoutineClaudeEnvironment.entries(fromLoginShellOutput: "") == [])
    }
}
