import Foundation
import Testing
@testable import ShellXAutomations

@Suite struct ShellXClaudeExecutableResolverTests {
    private let home = URL(filePath: "/Users/test")

    private func resolver(env: [String: String] = [:], executable: Set<String>, login: String? = nil) -> ShellXClaudeExecutableResolver {
        ShellXClaudeExecutableResolver(environment: env, home: home, isExecutable: { executable.contains($0) }, loginShellLookup: { login })
    }

    @Test func overrideWins() {
        let all: Set<String> = ["/custom/claude", "/Users/test/.claude/local/claude", "/usr/local/bin/claude"]
        #expect(resolver(env: ["SHELLX_CLAUDE_PATH": "/custom/claude"], executable: all).resolve() == "/custom/claude")
    }

    @Test func fixedOrder() {
        let all: Set<String> = ["/Users/test/.claude/local/claude", "/Users/test/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        #expect(resolver(executable: all).resolve() == "/Users/test/.claude/local/claude")
        #expect(resolver(executable: all.subtracting(["/Users/test/.claude/local/claude"])).resolve() == "/Users/test/.local/bin/claude")
        #expect(resolver(executable: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]).resolve() == "/opt/homebrew/bin/claude")
        #expect(resolver(executable: ["/usr/local/bin/claude"]).resolve() == "/usr/local/bin/claude")
    }

    @Test func missingOverrideFallsThrough() {
        #expect(resolver(env: ["SHELLX_CLAUDE_PATH": "/nope"], executable: ["/usr/local/bin/claude"]).resolve() == "/usr/local/bin/claude")
    }

    @Test func loginShellIsLastResort() {
        #expect(resolver(executable: ["/x/claude"], login: "/x/claude\n").resolve() == "/x/claude")
        #expect(resolver(executable: [], login: "/x/claude").resolve() == nil)
    }

    @Test func neverReturnsTheShellXWrapper() {
        let wrapper = "/Applications/ShellX.app/Contents/Resources/bin/shellx-claude-wrapper"
        #expect(resolver(executable: [wrapper], login: wrapper).resolve() == nil)
    }

    @Test func rejectsSymlinkToTheWrapper() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "resolver-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wrapper = dir.appending(path: "shellx-claude-wrapper")
        FileManager.default.createFile(atPath: wrapper.path, contents: Data())
        let link = dir.appending(path: "claude")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: wrapper)
        #expect(resolver(env: ["SHELLX_CLAUDE_PATH": link.path], executable: [link.path]).resolve() == nil)
    }

    @Test func loginShellOutputKeepsLastAbsoluteLine() {
        #expect(ShellXLoginShellClaudeLookup.absolutePath(fromOutput: "noise\n/x/claude\n\n") == "/x/claude")
        #expect(ShellXLoginShellClaudeLookup.absolutePath(fromOutput: "/x/claude\nclaude: aliased\n") == nil)
        #expect(ShellXLoginShellClaudeLookup.absolutePath(fromOutput: "") == nil)
    }
}
