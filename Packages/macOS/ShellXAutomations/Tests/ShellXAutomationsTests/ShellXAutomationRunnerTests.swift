import Foundation
import Testing
@testable import ShellXAutomations

private final class FakeTrasher: ShellXTrashing, @unchecked Sendable {
    func trash(_ url: URL) throws {}
}

private actor FakeClaude: ShellXClaudeLaunching {
    struct Call: Equatable { var prompt: String; var allowedTools: [String]; var resume: String?; var transcript: URL }
    private var queue: [ShellXClaudeResult]
    private(set) var calls: [Call] = []
    init(_ results: [ShellXClaudeResult]) { queue = results }
    func run(prompt: String, workingDirectory: URL, allowedTools: [String], resumeSessionId: String?, transcript: URL) async throws -> ShellXClaudeResult {
        calls.append(Call(prompt: prompt, allowedTools: allowedTools, resume: resumeSessionId, transcript: transcript))
        return queue.isEmpty ? ShellXClaudeResult(resultText: "extra") : queue.removeFirst()
    }
}

private actor VanishingRunClaude: ShellXClaudeLaunching {
    func run(prompt: String, workingDirectory: URL, allowedTools: [String], resumeSessionId: String?, transcript: URL) async throws -> ShellXClaudeResult {
        try FileManager.default.removeItem(at: transcript.deletingLastPathComponent())
        return ShellXClaudeResult(sessionId: "s1", resultText: "fine")
    }
}

private actor FakeNotifier: ShellXNotifying {
    private(set) var posted: [ShellXAutomationNotification] = []
    func post(_ n: ShellXAutomationNotification) async throws { posted.append(n) }
}

private func ok(_ text: String, session: String = "s1") -> ShellXClaudeResult {
    ShellXClaudeResult(sessionId: session, resultText: text)
}

private struct Fixture {
    let home: URL
    let store: ShellXAutomationStore
    let notifier = FakeNotifier()

    init() {
        home = FileManager.default.temporaryDirectory.appending(path: "shellx-runner-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let env = ShellXAutomationEnvironment(bundleIdentifier: "pro.shellx.desktop", home: home, cliPath: "/cli", notifierAppPath: "/n.app")
        store = ShellXAutomationStore(environment: env, trasher: FakeTrasher(), now: { Date() })
    }

    func cron(name: String = "nightly", notify: ShellXNotifySettings = ShellXNotifySettings()) async throws -> ShellXAutomation {
        let draft = ShellXAutomationDraft(
            kind: .cronjob, name: name, description: "Nightly job",
            schedule: ShellXSchedule(cron: "0 9 * * *", human: "Every day at 9:00"),
            workingDirectory: home.path, notify: notify, allowedTools: ["Read", "Grep"],
            skillMarkdown: "---\nname: \(name)\ndescription: Nightly job\n---\nDo the nightly thing\n"
        )
        return try await store.save(draft, replacing: nil)
    }

    func workflow() async throws -> ShellXAutomation {
        let draft = ShellXAutomationDraft(
            kind: .workflow, name: "flow", description: "Flow",
            schedule: ShellXSchedule(cron: "0 9 * * *", human: "Every day at 9:00"),
            workingDirectory: home.path, allowedTools: ["Read"],
            steps: [ShellXWorkflowStep(title: "One", prompt: "first"), ShellXWorkflowStep(title: "Two", prompt: "second"), ShellXWorkflowStep(title: "Three", prompt: "third")],
            skillMarkdown: "---\nname: flow\ndescription: Flow\n---\nFlow\n"
        )
        return try await store.save(draft, replacing: nil)
    }

    func runner(_ claude: (any ShellXClaudeLaunching)?) -> ShellXAutomationRunner {
        ShellXAutomationRunner(store: store, claude: claude, notifier: notifier, pid: 4242, now: { Date() })
    }
}

@Suite struct ShellXAutomationRunnerTests {
    @Test func doneNotifiesWithSummary() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let long = String(repeating: "x", count: 300)
        let claude = FakeClaude([ok(long)])
        let record = await f.runner(claude).run(id: a.id, trigger: .manual)
        #expect(record.status == .done && record.summary == long && record.unread)
        let posted = await f.notifier.posted
        #expect(posted.count == 1)
        #expect(posted[0].title == "nightly" && posted[0].body == String(repeating: "x", count: 180) + "…")
        #expect(posted[0].url.absoluteString == "shellx://automations/\(a.id)" && posted[0].group == a.id)
        let call = try #require(await claude.calls.first)
        #expect(call.prompt.hasPrefix("Do the nightly thing\n\nYou are running unattended."))
        #expect(call.prompt.hasSuffix("SHELLX_NEEDS_YOU: <short reason>."))
        #expect(!call.prompt.contains("name: nightly"))
        #expect(call.allowedTools == ["Read", "Grep"] && call.resume == nil)
        #expect(call.transcript.lastPathComponent == "output.jsonl")
    }

    @Test func failedWhenClaudeMissing() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let record = await f.runner(nil).run(id: a.id, trigger: .schedule)
        #expect(record.status == .failed && record.reason == "Claude Code was not found.")
        let posted = await f.notifier.posted
        #expect(posted.count == 1 && posted[0].body == "Claude Code was not found.")
    }

    @Test func failedOnNonZeroExit() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let r1 = await f.runner(FakeClaude([ShellXClaudeResult(exitCode: 1, stderrTail: "warn\nNot logged in\n")])).run(id: a.id, trigger: .manual)
        #expect(r1.status == .failed && r1.reason == "Not logged in")
        let r2 = await f.runner(FakeClaude([ShellXClaudeResult(resultText: "x", exitCode: 3)])).run(id: a.id, trigger: .manual)
        #expect(r2.reason == "Claude Code exited with status 3.")
    }

    @Test func failedWhenNoResultEvent() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let record = await f.runner(FakeClaude([ShellXClaudeResult(sessionId: "s1")])).run(id: a.id, trigger: .manual)
        #expect(record.status == .failed && record.reason == "Claude Code finished without a result.")
    }

    @Test func failedWhenResultIsError() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let record = await f.runner(FakeClaude([ShellXClaudeResult(resultText: "Boom", isError: true)])).run(id: a.id, trigger: .manual)
        #expect(record.status == .failed && record.reason == "Boom")
    }

    @Test func needsYouOnPermissionDenial() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let record = await f.runner(FakeClaude([ShellXClaudeResult(sessionId: "s9", resultText: "blocked", permissionDenials: ["Bash", "Write", "Bash"])])).run(id: a.id, trigger: .manual)
        #expect(record.status == .needsYou && record.reason == "Needs permission for: Bash, Write" && record.sessionId == "s9")
        #expect(await f.notifier.posted.first?.body == "Needs permission for: Bash, Write")
    }

    @Test func needsYouOnMarker() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let record = await f.runner(FakeClaude([ok("Found two options.\nSHELLX_NEEDS_YOU: pick one\n")])).run(id: a.id, trigger: .manual)
        #expect(record.status == .needsYou && record.reason == "pick one")
        #expect(record.summary == "Found two options.")
        #expect(await f.notifier.posted.first?.body == "pick one")
    }

    @Test func markerIsRemovedFromDoneSummaryToo() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let record = await f.runner(FakeClaude([ok("  All good.  ")])).run(id: a.id, trigger: .manual)
        #expect(record.summary == "All good.")
    }

    @Test func workflowResumesSessionAndStopsAtFailedStep() async throws {
        let f = Fixture()
        let a = try await f.workflow()
        let claude = FakeClaude([ok("one", session: "s1"), ShellXClaudeResult(sessionId: "s1", exitCode: 2, stderrTail: "bad"), ok("three")])
        let record = await f.runner(claude).run(id: a.id, trigger: .manual)
        let calls = await claude.calls
        #expect(calls.count == 2)
        #expect(calls[0].resume == nil && calls[1].resume == "s1")
        #expect(calls[0].prompt.hasPrefix("first") && calls[1].prompt.hasPrefix("second"))
        #expect(calls[0].transcript == calls[1].transcript)
        #expect(record.status == .failed && record.failedStep == 2 && record.reason == "bad")
    }

    @Test func workflowDoneUsesLastSummary() async throws {
        let f = Fixture()
        let a = try await f.workflow()
        let record = await f.runner(FakeClaude([ok("one"), ok("two"), ok("three")])).run(id: a.id, trigger: .manual)
        #expect(record.status == .done && record.summary == "three" && record.failedStep == nil)
    }

    @Test func notifyRespectsSettings() async throws {
        let f = Fixture()
        let onlyFailed = try await f.cron(name: "a-one", notify: ShellXNotifySettings(on: [.failed], targets: [.mac]))
        let phoneOnly = try await f.cron(name: "b-two", notify: ShellXNotifySettings(on: [.done], targets: [.iphone]))
        let r1 = await f.runner(FakeClaude([ok("fine")])).run(id: onlyFailed.id, trigger: .manual)
        let r2 = await f.runner(FakeClaude([ok("fine")])).run(id: phoneOnly.id, trigger: .manual)
        #expect(r1.status == .done && r2.status == .done)
        #expect(await f.notifier.posted.isEmpty)
    }

    @Test func skipsWhileLocked() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let fd = open(a.directory.appending(path: "run.lock").path, O_CREAT | O_RDWR, 0o644)
        #expect(fd >= 0)
        defer { close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        let claude = FakeClaude([ok("never")])
        let record = await f.runner(claude).run(id: a.id, trigger: .schedule)
        #expect(record.status == .skipped && !record.unread)
        #expect(await claude.calls.isEmpty)
        #expect(await f.notifier.posted.isEmpty)
        #expect(try await f.store.runs(id: a.id, limit: 10).isEmpty)
    }

    @Test func unknownIdAndSkillsFailWithoutWriting() async throws {
        let f = Fixture()
        let claude = FakeClaude([])
        let runner = f.runner(claude)
        let unknown = await runner.run(id: "nope", trigger: .manual)
        #expect(unknown.status == .failed && unknown.reason == "Unknown automation.")
        let skill = try await f.store.save(ShellXAutomationDraft(kind: .skill, name: "a-skill", description: "d", skillMarkdown: "---\nname: a-skill\ndescription: d\n---\nB\n"), replacing: nil)
        let r = await runner.run(id: skill.id, trigger: .manual)
        #expect(r.status == .failed && r.reason == "Skills are run by Claude Code, not on a schedule.")
        #expect(await claude.calls.isEmpty)
        #expect(await f.notifier.posted.isEmpty)
    }

    @Test func recordsRunAndTouchesStamp() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let stamp = f.home.appending(path: ".shellx/automations/.changed")
        try? FileManager.default.removeItem(at: stamp)
        let record = await f.runner(FakeClaude([ok("done it")])).run(id: a.id, trigger: .schedule)
        let stored = try await f.store.runs(id: a.id, limit: 5)
        #expect(stored.count == 1 && stored[0].summary == record.summary && stored[0].unread)
        #expect(stored[0].status == .done && stored[0].trigger == .schedule && stored[0].finishedAt != nil)
        #expect(FileManager.default.fileExists(atPath: stamp.path))
        // lock released: a second run can start
        let again = await f.runner(FakeClaude([ok("again")])).run(id: a.id, trigger: .manual)
        #expect(again.status == .done)
    }

    @Test func failedSaveReleasesLockAndReportsFailure() async throws {
        let f = Fixture()
        let a = try await f.cron()
        let record = await f.runner(VanishingRunClaude()).run(id: a.id, trigger: .manual)
        #expect(record.status == .failed)
        #expect(record.reason?.hasPrefix("ShellX could not save this run: ") == true)
        let posted = await f.notifier.posted
        #expect(posted.count == 1 && posted[0].body.hasPrefix("ShellX could not save this run"))
        let again = await f.runner(FakeClaude([ok("again")])).run(id: a.id, trigger: .manual)
        #expect(again.status == .done)
    }
}
