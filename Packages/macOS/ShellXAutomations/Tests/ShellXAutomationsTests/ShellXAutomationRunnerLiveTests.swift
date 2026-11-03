import Foundation
import Testing
@testable import ShellXAutomations

private final class RecordingTrasher: ShellXTrashing, @unchecked Sendable {
    func trash(_ url: URL) throws {}
}

private actor RecordingNotifier: ShellXNotifying {
    private(set) var posted: [ShellXAutomationNotification] = []
    func post(_ n: ShellXAutomationNotification) async throws { posted.append(n) }
}

/// Runs a real cronjob through the real `claude` CLI. Set `SHELLX_LIVE_CLAUDE=1` to enable; it spends a few tokens.
/// Everything lives under a temp home, so ~/.claude/skills, ~/.shellx and ~/Library/LaunchAgents are never touched.
@Suite struct ShellXAutomationRunnerLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHELLX_LIVE_CLAUDE"] == "1"))
    func realClaudeRunsCronjob() async throws {
        let fileManager = FileManager.default
        let tempHome = fileManager.temporaryDirectory.appending(path: "shellx-live-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempHome) }

        let environment = ShellXAutomationEnvironment(
            bundleIdentifier: "pro.shellx.desktop.livetest", home: tempHome, cliPath: "/usr/bin/true", notifierAppPath: "/nonexistent"
        )
        let store = ShellXAutomationStore(environment: environment, trasher: RecordingTrasher(), now: { Date() })
        let draft = ShellXAutomationDraft(
            kind: .cronjob, name: "live-ok", description: "Live test job",
            schedule: ShellXSchedule(cron: "0 8 * * *", human: "Every day at 8:00"),
            workingDirectory: tempHome.path,
            notify: ShellXNotifySettings(on: [.done, .failed, .needsYou], targets: [.mac]),
            allowedTools: [],
            skillMarkdown: "---\nname: live-ok\ndescription: Live test job\n---\nReply with the word ok.\n"
        )
        let automation = try await store.save(draft, replacing: nil)

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
        let claude = ShellXClaudeProcess(executable: resolved.path, environment: resolved.environment)

        let notifier = RecordingNotifier()
        let runner = ShellXAutomationRunner(store: store, claude: claude, notifier: notifier, pid: getpid(), now: { Date() })
        let record = await runner.run(id: automation.id, trigger: .manual)

        #expect(record.status == .done, "status \(record.status), reason: \(record.reason ?? "-")")
        #expect(record.summary?.lowercased().contains("ok") == true, "summary: \(record.summary ?? "nil")")
        let posted = await notifier.posted
        #expect(posted.count == 1)

        let runsRoot = environment.automationsRoot
        let transcripts = fileManager.enumerator(at: runsRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.lastPathComponent == "output.jsonl" } ?? []
        let transcript = try #require(transcripts.first, "no output.jsonl under \(runsRoot.path)")
        let size = (try fileManager.attributesOfItem(atPath: transcript.path)[.size] as? Int) ?? 0
        #expect(size > 0)

        let second = try await store.beginRun(id: automation.id, trigger: .manual, pid: getpid())
        #expect(second != nil, "run lock was not released")
    }
}
