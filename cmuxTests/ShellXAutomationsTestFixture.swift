import Foundation
import ShellXAutomations

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// One ordered log shared by the fake launchctl and the fake trasher, so tests can assert
/// that a job is booted out before its folder goes to the Trash.
final class ShellXAutomationsCallLog: @unchecked Sendable {
    // Test-only: appended from the scheduler's async calls and the store's sync trash.
    private let lock = NSLock()
    private var entries: [String] = []

    var all: [String] { lock.withLock { entries } }

    func append(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }
}

struct ShellXAutomationsFakeLaunchctl: ShellXLaunchctlRunning {
    let log: ShellXAutomationsCallLog

    func run(_ arguments: [String]) async throws -> (status: Int32, output: String) {
        log.append("launchctl " + arguments.joined(separator: " "))
        // Booting out a job that is not loaded reports status 3, as launchctl does.
        return (arguments.first == "bootout" ? 3 : 0, "")
    }
}

struct ShellXAutomationsFakeTrasher: ShellXTrashing {
    let log: ShellXAutomationsCallLog

    func trash(_ url: URL) throws {
        log.append("trash " + url.lastPathComponent)
        try FileManager.default.removeItem(at: url)
    }
}

/// A creator launcher that never starts a process; it records what the session writes.
final class ShellXAutomationsFakeCreatorLauncher: ShellXCreatorProcessLaunching, @unchecked Sendable {
    let log: ShellXAutomationsCallLog
    let lines: AsyncThrowingStream<String, any Error>
    let continuation: AsyncThrowingStream<String, any Error>.Continuation

    init(log: ShellXAutomationsCallLog) {
        self.log = log
        (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
    }

    func start(arguments: [String], workingDirectory: URL) async throws -> (
        lines: AsyncThrowingStream<String, any Error>,
        send: @Sendable (String) async throws -> Void,
        stop: @Sendable () async -> Void
    ) {
        let log = log
        return (lines, { log.append("creator.send " + $0) }, { log.append("creator.stop") })
    }
}

/// A temporary home with a store, a scheduler over a fake launchctl, and a library.
@MainActor
struct ShellXAutomationsFixture {
    let home: URL
    let environment: ShellXAutomationEnvironment
    let log = ShellXAutomationsCallLog()
    let store: ShellXAutomationStore
    let scheduler: ShellXLaunchAgentScheduler
    let library: ShellXAutomationsLibrary

    init() {
        home = FileManager.default.temporaryDirectory
            .appending(path: "shellx-automations-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        environment = ShellXAutomationEnvironment(
            bundleIdentifier: "pro.shellx.test",
            home: home,
            cliPath: "/Applications/ShellX.app/Contents/Resources/bin/shellx",
            notifierAppPath: "/Applications/ShellX.app/Contents/Library/ShellX Notifier.app"
        )
        store = ShellXAutomationStore(
            environment: environment,
            trasher: ShellXAutomationsFakeTrasher(log: log),
            now: { Date() }
        )
        scheduler = ShellXLaunchAgentScheduler(
            environment: environment,
            launchctl: ShellXAutomationsFakeLaunchctl(log: log),
            userID: 501
        )
        library = ShellXAutomationsLibrary(store: store, scheduler: scheduler, changeStampURL: environment.changeStampURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: home)
    }

    func cronDraft(_ name: String = "nightly") -> ShellXAutomationDraft {
        ShellXAutomationDraft(
            kind: .cronjob, name: name, description: "Nightly job",
            schedule: ShellXSchedule(cron: "0 9 * * *", human: "Every day at 9:00"),
            workingDirectory: home.path, allowedTools: ["Read"],
            skillMarkdown: "---\nname: \(name)\ndescription: Nightly job\n---\nDo it\n"
        )
    }

    func externalSkill(_ name: String) throws {
        let folder = environment.skillsRoot.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: Theirs\n---\nBody\n".utf8).write(to: folder.appending(path: "SKILL.md"))
    }
}
