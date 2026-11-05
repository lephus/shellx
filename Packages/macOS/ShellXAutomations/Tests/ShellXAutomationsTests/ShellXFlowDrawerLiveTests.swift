import Foundation
import Testing
@testable import ShellXAutomations

/// Draws a real skill through the real `claude` CLI. Set `SHELLX_LIVE_CLAUDE=1` to enable; it spends a few tokens.
@Suite struct ShellXFlowDrawerLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHELLX_LIVE_CLAUDE"] == "1"))
    func drawsDiskCleanup() async throws {
        let fileManager = FileManager.default
        let tempHome = fileManager.temporaryDirectory.appending(path: "shellx-live-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempHome) }

        let processEnvironment = ProcessInfo.processInfo.environment
        let resolver = ShellXClaudeExecutableResolver(
            environment: processEnvironment,
            home: tempHome,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
            loginShellLookup: { ShellXLoginShellClaudeLookup()() }
        )
        let claudeEnvironment = ShellXRoutineClaudeEnvironment.live(inherited: processEnvironment, home: tempHome)
        let launch: (path: String, environment: [String: String])? = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let found = resolver.resolve().map { path in (path, claudeEnvironment.environment(forClaudeAt: path)) }
                continuation.resume(returning: found)
            }
        }
        let resolved = try #require(launch, "claude was not found")
        let claude = ShellXFlowDrawer.claudeProcess(executable: resolved.path, environment: resolved.environment)

        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let skill = try String(contentsOf: fixtures.appending(path: "disk-cleanup-SKILL.md"), encoding: .utf8)
        // Tests run from the package; the rules file sits at the repo root.
        let rulesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/shellx-automations/flow-rules.md")
        let rules = try String(contentsOf: rulesURL, encoding: .utf8)

        let drawer = ShellXFlowDrawer(launcher: claude, rules: rules, workingDirectory: tempHome)
        let flow = try await drawer.draw(skillMarkdown: skill)

        #expect(flow.nodes.contains { $0.type == .askUser }, "flow: \(flow)")
        #expect(flow.nodes.contains { $0.type == .step }, "flow: \(flow)")
    }
}
