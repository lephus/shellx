import Foundation
import Testing
@testable import ShellXAutomations

private final class FakeTrasher: ShellXTrashing, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var trashed: [URL] { lock.withLock { urls } }
    func trash(_ url: URL) throws { lock.withLock { urls.append(url) } }
}

private final class TickingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    func tick() -> Date { lock.withLock { defer { current += 1 }; return current } }
}

private struct Fixture {
    let home: URL
    let environment: ShellXAutomationEnvironment
    let trasher = FakeTrasher()
    let clock = TickingClock(Date(timeIntervalSince1970: 1_800_000_000))
    let store: ShellXAutomationStore

    init() {
        home = FileManager.default.temporaryDirectory.appending(path: "shellx-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let env = ShellXAutomationEnvironment(bundleIdentifier: "pro.shellx.desktop", home: home, cliPath: "/cli", notifierAppPath: "/n.app")
        environment = env
        let clock = self.clock
        store = ShellXAutomationStore(environment: env, trasher: trasher, now: { clock.tick() })
    }

    func skillDraft(_ name: String = "pr-digest") -> ShellXAutomationDraft {
        ShellXAutomationDraft(
            kind: .skill, name: name, description: "Digest PRs",
            skillMarkdown: "---\nname: \(name)\ndescription: Digest PRs\n---\nBody\n"
        )
    }

    func cronDraft(_ name: String = "nightly") -> ShellXAutomationDraft {
        ShellXAutomationDraft(
            kind: .cronjob, name: name, description: "Nightly job",
            schedule: ShellXSchedule(cron: "0 9 * * *", human: "Every day at 9:00"),
            workingDirectory: "/tmp", allowedTools: ["Read"],
            skillMarkdown: "---\nname: \(name)\ndescription: Nightly job\n---\nDo it\n"
        )
    }

    func record(_ trigger: ShellXRunTrigger = .manual) -> ShellXRunRecord {
        ShellXRunRecord(status: .done, trigger: trigger, startedAt: Date(timeIntervalSince1970: 1_800_000_000), finishedAt: Date(timeIntervalSince1970: 1_800_000_005), summary: "ok")
    }
}

@Suite struct ShellXAutomationStoreTests {
    @Test func savesSkillWhereClaudeLoadsIt() async throws {
        let f = Fixture()
        let draft = f.skillDraft()
        let saved = try await f.store.save(draft, replacing: nil)
        let dir = f.environment.skillsRoot.appending(path: "pr-digest")
        #expect(try String(contentsOf: dir.appending(path: "SKILL.md"), encoding: .utf8) == draft.skillMarkdown)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: ".shellx.json").path))
        #expect(saved.directory.standardizedFileURL == dir.standardizedFileURL)
        let listed = try await f.store.list()
        #expect(listed.count == 1)
        #expect(listed[0].origin == .shellx && listed[0].kind == .skill)
        #expect(listed[0].name == "pr-digest" && listed[0].description == "Digest PRs")
        #expect(listed[0].id == saved.id)
    }

    @Test func savesCronjob() async throws {
        let f = Fixture()
        let draft = f.cronDraft()
        let saved = try await f.store.save(draft, replacing: nil)
        let dir = f.environment.automationsRoot.appending(path: saved.id)
        #expect(saved.directory.standardizedFileURL == dir.standardizedFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let onDisk = try decoder.decode(ShellXAutomation.self, from: Data(contentsOf: dir.appending(path: "automation.json")))
        #expect(onDisk.name == draft.name && onDisk.schedule == draft.schedule)
        #expect(onDisk.workingDirectory == "/tmp" && onDisk.allowedTools == ["Read"])
        #expect(onDisk.enabled == true)
        #expect(try String(contentsOf: dir.appending(path: "SKILL.md"), encoding: .utf8) == draft.skillMarkdown)
        let listed = try await f.store.list()
        #expect(listed.map(\.id) == [saved.id])
        #expect(listed[0].directory.standardizedFileURL == dir.standardizedFileURL)
        #expect(try await f.store.automation(named: "nightly")?.id == saved.id)
        #expect(try await f.store.automation(id: saved.id)?.directory.standardizedFileURL == dir.standardizedFileURL)
    }

    @Test func listsExternalSkills() async throws {
        let f = Fixture()
        let other = f.environment.skillsRoot.appending(path: "other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "---\nname: other\ndescription: From elsewhere\n---\n".write(to: other.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let bad = f.environment.skillsRoot.appending(path: "broken")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try "no frontmatter".write(to: bad.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: f.environment.skillsRoot.appending(path: "synced"), withIntermediateDirectories: true)

        let listed = try await f.store.list()
        #expect(Set(listed.map(\.id)) == ["external:other", "external:broken"])
        let ext = try #require(listed.first { $0.id == "external:other" })
        #expect(ext.origin == .external && ext.kind == .skill && ext.enabled)
        #expect(ext.description == "From elsewhere" && ext.notify == ShellXNotifySettings(on: [], targets: []))
        let broken = try #require(listed.first { $0.id == "external:broken" })
        #expect(broken.name == "broken" && broken.description == "")
        #expect(try await f.store.automation(id: "external:other")?.name == "other")
    }

    @Test func savesNeverEscapeRoots() async throws {
        let f = Fixture()
        for name in ["../evil", "a/b", "My Skill", "caf\u{E9}", "cafe\u{301}", "a--b", "", String(repeating: "a", count: 65)] {
            for kind in [ShellXAutomationKind.skill, .cronjob] {
                var draft = f.skillDraft(name)
                draft.kind = kind
                await #expect(throws: ShellXAutomationStoreError.self) { try await f.store.save(draft, replacing: nil) }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: f.environment.skillsRoot.deletingLastPathComponent().appending(path: "evil").path))
        #expect(!FileManager.default.fileExists(atPath: f.environment.skillsRoot.path))
        #expect(!FileManager.default.fileExists(atPath: f.environment.automationsRoot.path))
    }

    @Test func editRenamesSkillFolder() async throws {
        let f = Fixture()
        let first = try await f.store.save(f.skillDraft("old-name"), replacing: nil)
        let second = try await f.store.save(f.skillDraft("new-name"), replacing: first.id)
        #expect(second.id == first.id && second.name == "new-name")
        #expect(!FileManager.default.fileExists(atPath: f.environment.skillsRoot.appending(path: "old-name").path))
        #expect(FileManager.default.fileExists(atPath: f.environment.skillsRoot.appending(path: "new-name/SKILL.md").path))
        #expect(try await f.store.list().count == 1)
        #expect(second.createdAt == first.createdAt)
    }

    @Test func editKeepsCronjobEnabledState() async throws {
        let f = Fixture()
        let first = try await f.store.save(f.cronDraft(), replacing: nil)
        _ = try await f.store.setEnabled(id: first.id, false)
        var draft = f.cronDraft("renamed")
        draft.description = "Changed"
        let second = try await f.store.save(draft, replacing: first.id)
        #expect(second.id == first.id && second.name == "renamed" && second.enabled == false)
        #expect(second.createdAt == first.createdAt)
    }

    @Test func setEnabledAppliesToAutomationsNotSkills() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        let off = try await f.store.setEnabled(id: cron.id, false)
        #expect(off.enabled == false)
        #expect(try await f.store.automation(id: cron.id)?.enabled == false)
        let skill = try await f.store.save(f.skillDraft(), replacing: nil)
        await #expect(throws: ShellXAutomationStoreError.self) { try await f.store.setEnabled(id: skill.id, false) }
    }

    @Test func deleteMovesToTrash() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        let skill = try await f.store.save(f.skillDraft(), replacing: nil)
        let other = f.environment.skillsRoot.appending(path: "other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "---\nname: other\n---\n".write(to: other.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try await f.store.delete(id: cron.id)
        try await f.store.delete(id: skill.id)
        try await f.store.delete(id: "external:other")
        #expect(f.trasher.trashed.map(\.lastPathComponent) == [cron.id, "pr-digest", "other"])
        #expect(FileManager.default.fileExists(atPath: other.path), "the fake trasher moves nothing, so nothing was removed with removeItem")
        #expect(FileManager.default.fileExists(atPath: cron.directory.path))
    }

    @Test func keepsThirtyRuns() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        var first: URL?
        for _ in 0..<31 {
            let dir = try #require(try await f.store.beginRun(id: cron.id, trigger: .schedule, pid: getpid(), isProcessAlive: { _ in false }))
            if first == nil { first = dir }
            try await f.store.finishRun(id: cron.id, runDirectory: dir, record: f.record(), pid: getpid())
        }
        let runsDir = f.environment.automationsRoot.appending(path: "\(cron.id)/runs")
        let names = try FileManager.default.contentsOfDirectory(atPath: runsDir.path)
        #expect(names.count == 30)
        #expect(!FileManager.default.fileExists(atPath: try #require(first).path))
        #expect(try await f.store.runs(id: cron.id, limit: 100).count == 30)
        #expect(try await f.store.runs(id: cron.id, limit: 5).count == 5)
        #expect(!FileManager.default.fileExists(atPath: runsDir.deletingLastPathComponent().appending(path: "run.lock").path))
    }

    @Test func skipsWhileLocked() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        let first = try await f.store.beginRun(id: cron.id, trigger: .manual, pid: 4242, isProcessAlive: { _ in true })
        #expect(first != nil)
        let second = try await f.store.beginRun(id: cron.id, trigger: .schedule, pid: 4343, isProcessAlive: { $0 == 4242 })
        #expect(second == nil)
        let lock = try String(contentsOf: cron.directory.appending(path: "run.lock"), encoding: .utf8)
        #expect(lock.trimmingCharacters(in: .whitespacesAndNewlines) == "4242")
        let running = try await f.store.automation(id: cron.id)?.lastRun
        #expect(running?.status == .running)
    }

    @Test func takesOverStaleLock() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        _ = try await f.store.beginRun(id: cron.id, trigger: .manual, pid: 4242, isProcessAlive: { _ in true })
        let next = try await f.store.beginRun(id: cron.id, trigger: .schedule, pid: getpid(), isProcessAlive: { _ in false })
        let dir = try #require(next)
        let lock = try String(contentsOf: cron.directory.appending(path: "run.lock"), encoding: .utf8)
        #expect(lock.trimmingCharacters(in: .whitespacesAndNewlines) == "\(getpid())")
        try await f.store.finishRun(id: cron.id, runDirectory: dir, record: f.record(), pid: getpid())
        #expect(!FileManager.default.fileExists(atPath: cron.directory.appending(path: "run.lock").path))
    }

    @Test func finishRunLeavesForeignLockAlone() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        let dir = try #require(try await f.store.beginRun(id: cron.id, trigger: .manual, pid: 4242, isProcessAlive: { _ in false }))
        try await f.store.finishRun(id: cron.id, runDirectory: dir, record: f.record(), pid: 9999)
        #expect(FileManager.default.fileExists(atPath: cron.directory.appending(path: "run.lock").path))
    }

    @Test func runDirectoryGetsSuffixOnCollision() async throws {
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let f = Fixture()
        let store = ShellXAutomationStore(environment: f.environment, trasher: f.trasher, now: { fixed })
        let cron = try await store.save(f.cronDraft(), replacing: nil)
        let a = try #require(try await store.beginRun(id: cron.id, trigger: .manual, pid: getpid(), isProcessAlive: { _ in false }))
        try await store.finishRun(id: cron.id, runDirectory: a, record: f.record(), pid: getpid())
        let b = try #require(try await store.beginRun(id: cron.id, trigger: .manual, pid: getpid(), isProcessAlive: { _ in false }))
        #expect(a.lastPathComponent == "20270115-080000")
        #expect(b.lastPathComponent == "20270115-080000-2")
    }

    @Test func lastRunAndMarkRead() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        let dir = try #require(try await f.store.beginRun(id: cron.id, trigger: .manual, pid: getpid(), isProcessAlive: { _ in false }))
        try await f.store.finishRun(id: cron.id, runDirectory: dir, record: f.record(), pid: getpid())
        #expect(try await f.store.automation(id: cron.id)?.lastRun?.unread == true)
        try await f.store.markRead(id: cron.id)
        let after = try await f.store.automation(id: cron.id)?.lastRun
        #expect(after?.unread == false && after?.status == .done)
    }

    @Test func changeStampIsAtomic() async throws {
        let f = Fixture()
        try await f.store.touchChangeStamp()
        let url = f.environment.changeStampURL
        func fileNumber() throws -> Int {
            try #require(FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int)
        }
        let before = try fileNumber()
        try await f.store.touchChangeStamp()
        #expect(try fileNumber() != before, "an atomic replace swaps the directory entry")
        _ = try await f.store.save(f.cronDraft(), replacing: nil)
        #expect(try Data(contentsOf: url).isEmpty == false)
    }

    @Test func emptyFreshLockIsHeldAndOldOneTakenOver() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        let lock = cron.directory.appending(path: "run.lock")
        try Data().write(to: lock)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)], ofItemAtPath: lock.path)
        let held = try await f.store.beginRun(id: cron.id, trigger: .manual, pid: 7, isProcessAlive: { _ in false })
        #expect(held == nil)
        let old = Date(timeIntervalSince1970: 1_800_000_000 - 3600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: lock.path)
        let dir = try await f.store.beginRun(id: cron.id, trigger: .manual, pid: 7, isProcessAlive: { _ in false })
        #expect(dir != nil)
        #expect(try String(contentsOf: lock, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "7")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: cron.directory.path).filter { $0.hasPrefix(".run.lock.") }
        #expect(leftovers.isEmpty)
    }

    @Test func finishRunRemovesLockOnlyForMatchingPid() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        let dir = try #require(try await f.store.beginRun(id: cron.id, trigger: .manual, pid: 4242, isProcessAlive: { _ in false }))
        let lock = cron.directory.appending(path: "run.lock")
        try await f.store.finishRun(id: cron.id, runDirectory: dir, record: f.record(), pid: 1)
        #expect(FileManager.default.fileExists(atPath: lock.path))
        try await f.store.finishRun(id: cron.id, runDirectory: dir, record: f.record(), pid: 4242)
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }

    @Test func finishRunRejectsNonRunDirectories() async throws {
        let f = Fixture()
        let cron = try await f.store.save(f.cronDraft(), replacing: nil)
        let runs = cron.directory.appending(path: "runs", directoryHint: .isDirectory)
        for bad in [runs.appending(path: ".."), runs.appending(path: "x/.."), runs.appending(path: "notes")] {
            await #expect(throws: ShellXAutomationStoreError.self) {
                try await f.store.finishRun(id: cron.id, runDirectory: bad, record: f.record(), pid: 1)
            }
        }
    }
}
