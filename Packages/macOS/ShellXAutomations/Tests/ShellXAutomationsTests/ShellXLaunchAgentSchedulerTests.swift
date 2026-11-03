import Foundation
import Testing
@testable import ShellXAutomations

private actor FakeLaunchctl: ShellXLaunchctlRunning {
    private(set) var calls: [[String]] = []
    var bootstrapStatus: Int32 = 0
    var bootoutStatus: Int32 = 0
    func setBootstrapStatus(_ s: Int32) { bootstrapStatus = s }
    func setBootoutStatus(_ s: Int32) { bootoutStatus = s }
    func reset() { calls = [] }
    func run(_ arguments: [String]) async throws -> (status: Int32, output: String) {
        calls.append(arguments)
        if arguments.first == "bootstrap" { return (bootstrapStatus, bootstrapStatus == 0 ? "" : "Bootstrap failed: 5") }
        return (bootoutStatus, bootoutStatus == 0 ? "" : (bootoutStatus == 3 ? "Boot-out failed: 3: No such process" : "Boot-out failed: \(bootoutStatus)"))
    }
}

private struct Fixture {
    let home = FileManager.default.temporaryDirectory.appending(path: "shellx-sched-\(UUID().uuidString)", directoryHint: .isDirectory)
    let fake = FakeLaunchctl()
    let environment: ShellXAutomationEnvironment
    let scheduler: ShellXLaunchAgentScheduler

    init(bundle: String = "pro.shellx.desktop", cli: String = "/Apps/shellx") {
        let env = ShellXAutomationEnvironment(bundleIdentifier: bundle, home: home, cliPath: cli, notifierAppPath: "/n.app")
        environment = env
        scheduler = ShellXLaunchAgentScheduler(environment: env, launchctl: fake, userID: 501)
        try? FileManager.default.createDirectory(at: env.launchAgentsDirectory, withIntermediateDirectories: true)
    }

    func scheduler(cli: String) -> ShellXLaunchAgentScheduler {
        let env = ShellXAutomationEnvironment(bundleIdentifier: environment.bundleIdentifier, home: home, cliPath: cli, notifierAppPath: "/n.app")
        return ShellXLaunchAgentScheduler(environment: env, launchctl: fake, userID: 501)
    }

    func automation(_ id: String = "A1", kind: ShellXAutomationKind = .cronjob, enabled: Bool = true,
                    cron: String? = "30 9 * * 1-5", workingDirectory: String? = "/work") -> ShellXAutomation {
        ShellXAutomation(
            id: id, kind: kind, name: "job", description: "d",
            schedule: cron.map { ShellXSchedule(cron: $0, human: "h") },
            workingDirectory: workingDirectory, enabled: enabled,
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
            directory: home.appending(path: ".shellx/automations/\(id)", directoryHint: .isDirectory)
        )
    }

    func plistURL(_ label: String) -> URL { environment.launchAgentsDirectory.appending(path: label + ".plist") }
    func exists(_ label: String) -> Bool { FileManager.default.fileExists(atPath: plistURL(label).path) }
}

@Suite struct ShellXLaunchAgentSchedulerTests {
    @Test func plistMatchesSpec() throws {
        let f = Fixture()
        let a = f.automation()
        let dict = try #require(try PropertyListSerialization.propertyList(from: f.scheduler.plistData(for: a), format: nil) as? [String: Any])
        #expect(dict["Label"] as? String == "pro.shellx.automation.A1")
        #expect(dict["ProgramArguments"] as? [String] == ["/Apps/shellx", "routine", "run", "A1", "--trigger", "schedule"])
        let intervals = try #require(dict["StartCalendarInterval"] as? [[String: Int]])
        #expect(intervals == (try ShellXCronExpression("30 9 * * 1-5").launchdCalendarIntervals()))
        let log = a.directory.appending(path: "launchd.log").path
        #expect(dict["StandardOutPath"] as? String == log)
        #expect(dict["StandardErrorPath"] as? String == log)
        // launchd's chdir into a TCC-protected or deleted project folder would stop the job from ever starting;
        // the runner gives claude the project folder itself.
        #expect(dict["WorkingDirectory"] as? String == a.directory.path)
        #expect(dict["ProcessType"] as? String == "Background")
        #expect(dict["RunAtLoad"] == nil)
    }

    @Test func installBootsOutThenBootstraps() async throws {
        let f = Fixture()
        try await f.scheduler.install(f.automation())
        let plist = f.plistURL("pro.shellx.automation.A1").path
        #expect(await f.fake.calls == [
            ["bootout", "gui/501/pro.shellx.automation.A1"],
            ["bootstrap", "gui/501", plist],
        ])
        #expect(f.exists("pro.shellx.automation.A1"))
    }

    @Test func installIgnoresBootoutFailure() async throws {
        let f = Fixture()
        await f.fake.setBootoutStatus(3)
        try await f.scheduler.install(f.automation())
        #expect(f.exists("pro.shellx.automation.A1"))
    }

    @Test func bootstrapFailureThrowsWithOutput() async throws {
        let f = Fixture()
        await f.fake.setBootstrapStatus(5)
        await #expect(throws: ShellXLaunchAgentError.bootstrapFailed(status: 5, output: "Bootstrap failed: 5")) {
            try await f.scheduler.install(f.automation())
        }
    }

    @Test func removeBootsOutAndDeletesPlist() async throws {
        let f = Fixture()
        try await f.scheduler.install(f.automation())
        await f.fake.reset()
        try await f.scheduler.remove(id: "A1")
        #expect(await f.fake.calls == [["bootout", "gui/501/pro.shellx.automation.A1"]])
        #expect(!f.exists("pro.shellx.automation.A1"))
    }

    @Test func removeOnlyOwnLabels() async throws {
        let f = Fixture()
        let foreign = f.plistURL("com.google.keystone.agent")
        try Data("foreign".utf8).write(to: foreign)
        try await f.scheduler.sync([])
        #expect(await f.fake.calls.isEmpty)
        #expect(try Data(contentsOf: foreign) == Data("foreign".utf8))
        try await f.scheduler.remove(id: "../x")
        try await f.scheduler.remove(id: "dev.x")
        #expect(await f.fake.calls.isEmpty)
    }

    @Test func releaseSyncIgnoresDevPlists() async throws {
        let f = Fixture()
        let dev = f.plistURL("pro.shellx.automation.dev.pro.shellx.desktop.debug.ABC")
        try Data("dev".utf8).write(to: dev)
        try await f.scheduler.sync([])
        #expect(await f.fake.calls.isEmpty)
        #expect(try Data(contentsOf: dev) == Data("dev".utf8))
    }

    @Test func syncInstallsMissingAndSkipsUpToDate() async throws {
        let f = Fixture()
        let a = f.automation()
        try await f.scheduler.sync([a])
        #expect(await f.fake.calls.count == 2)
        await f.fake.reset()
        try await f.scheduler.sync([a])
        #expect(await f.fake.calls.isEmpty)
    }

    @Test func syncRewritesWhenCliPathChanged() async throws {
        let f = Fixture()
        let a = f.automation()
        try await f.scheduler.sync([a])
        await f.fake.reset()
        let moved = f.scheduler(cli: "/New/shellx")
        try await moved.sync([a])
        #expect(await f.fake.calls.count == 2)
        let dict = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: f.plistURL("pro.shellx.automation.A1")), format: nil) as? [String: Any])
        #expect((dict["ProgramArguments"] as? [String])?.first == "/New/shellx")
    }

    @Test func disabledAutomationIsRemoved() async throws {
        let f = Fixture()
        try await f.scheduler.sync([f.automation()])
        await f.fake.reset()
        try await f.scheduler.sync([f.automation(enabled: false)])
        #expect(await f.fake.calls == [["bootout", "gui/501/pro.shellx.automation.A1"]])
        #expect(!f.exists("pro.shellx.automation.A1"))
    }

    @Test func skillsAreNeverScheduled() async throws {
        let f = Fixture()
        try await f.scheduler.sync([f.automation("S1", kind: .skill), f.automation("N1", cron: nil)])
        #expect(await f.fake.calls.isEmpty)
        #expect(!f.exists("pro.shellx.automation.S1"))
    }

    @Test func failedBootstrapDeletesNewPlistSoSyncRetries() async throws {
        let f = Fixture()
        await f.fake.setBootstrapStatus(5)
        await #expect(throws: ShellXLaunchAgentSyncError.self) { try await f.scheduler.sync([f.automation()]) }
        #expect(!f.exists("pro.shellx.automation.A1"))
        await f.fake.setBootstrapStatus(0)
        await f.fake.reset()
        try await f.scheduler.sync([f.automation()])
        #expect(await f.fake.calls.count == 2)
        #expect(f.exists("pro.shellx.automation.A1"))
    }

    @Test func failedBootstrapRestoresPreviousPlist() async throws {
        let f = Fixture()
        try await f.scheduler.install(f.automation())
        let before = try Data(contentsOf: f.plistURL("pro.shellx.automation.A1"))
        await f.fake.setBootstrapStatus(5)
        await #expect(throws: ShellXLaunchAgentError.self) {
            try await f.scheduler.install(f.automation(cron: "0 1 * * *"))
        }
        #expect(try Data(contentsOf: f.plistURL("pro.shellx.automation.A1")) == before)
    }

    @Test func syncProcessesEveryItemAndReportsFailures() async throws {
        let f = Fixture()
        do {
            try await f.scheduler.sync([f.automation("BAD", cron: "nope"), f.automation("GOOD")])
            Issue.record("expected error")
        } catch let error as ShellXLaunchAgentSyncError {
            #expect(error.failures.map(\.id) == ["BAD"])
        }
        #expect(f.exists("pro.shellx.automation.GOOD"))
    }

    @Test func unsafeIdentifiersAreRejected() async throws {
        let f = Fixture()
        let bad = f.automation("../../x")
        #expect(throws: ShellXLaunchAgentError.invalidIdentifier(id: "../../x")) { try f.scheduler.plistData(for: bad) }
        await #expect(throws: ShellXLaunchAgentError.invalidIdentifier(id: "../../x")) { try await f.scheduler.install(bad) }
        #expect(await f.fake.calls.isEmpty)
    }

    @Test func removeThrowsOnRealBootoutFailureAndKeepsPlist() async throws {
        let f = Fixture()
        try await f.scheduler.install(f.automation())
        await f.fake.setBootoutStatus(5)
        await #expect(throws: ShellXLaunchAgentError.bootoutFailed(status: 5, output: "Boot-out failed: 5")) { try await f.scheduler.remove(id: "A1") }
        #expect(f.exists("pro.shellx.automation.A1"))
    }

    @Test func workflowsAreScheduled() async throws {
        let f = Fixture()
        try await f.scheduler.sync([f.automation("W1", kind: .workflow)])
        #expect(f.exists("pro.shellx.automation.W1"))
    }
}
