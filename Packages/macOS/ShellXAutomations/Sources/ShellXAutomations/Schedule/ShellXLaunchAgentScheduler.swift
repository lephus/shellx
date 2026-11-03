public import Foundation

/// Installs, removes and reconciles the launchd jobs behind scheduled automations.
///
/// Only plists whose label is `labelPrefix + <id>` (an id contains no `.`) are ever touched.
public struct ShellXLaunchAgentScheduler: Sendable {
    private let environment: ShellXAutomationEnvironment
    private let launchctl: any ShellXLaunchctlRunning
    private let userID: uid_t
    // FileManager file operations are thread-safe; used only for plain file I/O here.
    private nonisolated(unsafe) let fileManager: FileManager

    /// Creates a scheduler for `environment`.
    public init(
        environment: ShellXAutomationEnvironment,
        launchctl: any ShellXLaunchctlRunning,
        userID: uid_t,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.launchctl = launchctl
        self.userID = userID
        self.fileManager = fileManager
    }

    /// The launchd label for an automation id.
    public func label(for id: String) -> String { environment.labelPrefix + id }

    /// The plist content launchd should run for `automation`.
    public func plistData(for automation: ShellXAutomation) throws -> Data {
        guard let schedule = automation.schedule else {
            throw ShellXLaunchAgentError.notScheduled(id: automation.id)
        }
        let intervals = try ShellXCronExpression(schedule.cron).launchdCalendarIntervals()
        let log = automation.directory.appending(path: "launchd.log").path
        let dictionary: [String: Any] = [
            "Label": label(for: automation.id),
            "ProgramArguments": [environment.cliPath, "routine", "run", automation.id, "--trigger", "schedule"],
            "StartCalendarInterval": intervals,
            "StandardOutPath": log,
            "StandardErrorPath": log,
            "WorkingDirectory": automation.workingDirectory ?? automation.directory.path,
            "ProcessType": "Background",
        ]
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    /// Writes the plist, then reloads the job.
    public func install(_ automation: ShellXAutomation) async throws {
        let data = try plistData(for: automation)
        let url = plistURL(for: automation.id)
        try fileManager.createDirectory(at: environment.launchAgentsDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        _ = try await launchctl.run(["bootout", "gui/\(userID)/\(label(for: automation.id))"])
        let result = try await launchctl.run(["bootstrap", "gui/\(userID)", url.path])
        guard result.status == 0 else {
            throw ShellXLaunchAgentError.bootstrapFailed(status: result.status, output: result.output)
        }
    }

    /// Unloads the job and deletes its plist.
    public func remove(id: String) async throws {
        guard Self.isIdentifier(id) else { return }
        _ = try await launchctl.run(["bootout", "gui/\(userID)/\(label(for: id))"])
        let url = plistURL(for: id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    /// Makes installed jobs match `automations`: installs missing or changed ones, removes orphans.
    public func sync(_ automations: [ShellXAutomation]) async throws {
        let scheduled = automations.filter {
            ($0.kind == .cronjob || $0.kind == .workflow) && $0.enabled && $0.schedule != nil
        }
        let wanted = Set(scheduled.map(\.id))
        for id in installedIdentifiers() where !wanted.contains(id) {
            try await remove(id: id)
        }
        for automation in scheduled {
            let expected = try plistData(for: automation)
            if let existing = try? Data(contentsOf: plistURL(for: automation.id)), Self.sameDictionary(existing, expected) {
                continue
            }
            try await install(automation)
        }
    }

    private func plistURL(for id: String) -> URL {
        environment.launchAgentsDirectory.appending(path: label(for: id) + ".plist")
    }

    private static func isIdentifier(_ id: String) -> Bool {
        !id.isEmpty && !id.contains(".") && !id.contains("/")
    }

    private func installedIdentifiers() -> [String] {
        let names = (try? fileManager.contentsOfDirectory(atPath: environment.launchAgentsDirectory.path)) ?? []
        let prefix = environment.labelPrefix
        return names.compactMap { name in
            guard name.hasPrefix(prefix), name.hasSuffix(".plist") else { return nil }
            let id = String(name.dropFirst(prefix.count).dropLast(".plist".count))
            return Self.isIdentifier(id) ? id : nil
        }
    }

    private static func sameDictionary(_ a: Data, _ b: Data) -> Bool {
        guard let x = try? PropertyListSerialization.propertyList(from: a, format: nil) as? NSDictionary,
              let y = try? PropertyListSerialization.propertyList(from: b, format: nil) as? NSDictionary
        else { return false }
        return x.isEqual(y)
    }
}
