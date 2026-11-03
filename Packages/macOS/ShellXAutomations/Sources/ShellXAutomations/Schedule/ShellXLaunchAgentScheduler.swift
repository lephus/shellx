public import Foundation

/// Installs, removes and reconciles the launchd jobs behind scheduled automations.
///
/// Only plists whose label is `labelPrefix + <id>` (an id contains no `.`) are ever touched.
public struct ShellXLaunchAgentScheduler: Sendable {
    private let environment: ShellXAutomationEnvironment
    private let launchctl: any ShellXLaunchctlRunning
    private let userID: uid_t
    // FileManager is not Sendable on this SDK; it is only used for plain, thread-safe file I/O.
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
        guard Self.isIdentifier(automation.id) else {
            throw ShellXLaunchAgentError.invalidIdentifier(id: automation.id)
        }
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
            // Never the project folder: launchd's chdir into a TCC-protected or deleted folder fails and the job never
            // starts. The runner gives claude the project folder as its working directory.
            "WorkingDirectory": automation.directory.path,
            "ProcessType": "Background",
        ]
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    /// Writes the plist, then reloads the job. On failure the previous plist is restored (or the new one deleted).
    public func install(_ automation: ShellXAutomation) async throws {
        let data = try plistData(for: automation)
        let url = plistURL(for: automation.id)
        let previous = try? Data(contentsOf: url)
        try fileManager.createDirectory(at: environment.launchAgentsDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        do {
            _ = try await launchctl.run(["bootout", "gui/\(userID)/\(label(for: automation.id))"])
            let result = try await launchctl.run(["bootstrap", "gui/\(userID)", url.path])
            guard result.status == 0 else {
                throw ShellXLaunchAgentError.bootstrapFailed(status: result.status, output: result.output)
            }
        } catch {
            if let previous {
                try? previous.write(to: url, options: .atomic)
            } else {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }
    }

    /// Unloads the job and deletes its plist.
    public func remove(id: String) async throws {
        guard Self.isIdentifier(id) else { return }
        let result = try await launchctl.run(["bootout", "gui/\(userID)/\(label(for: id))"])
        guard result.status == 0 || Self.isNotLoaded(result) else {
            throw ShellXLaunchAgentError.bootoutFailed(status: result.status, output: result.output)
        }
        let url = plistURL(for: id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    /// Makes installed jobs match `automations`: installs missing or changed ones, removes orphans.
    /// Every item is processed; failures are collected and thrown together as ``ShellXLaunchAgentSyncError``.
    public func sync(_ automations: [ShellXAutomation]) async throws {
        let scheduled = automations.filter {
            ($0.kind == .cronjob || $0.kind == .workflow) && $0.enabled && $0.schedule != nil
        }
        let wanted = Set(scheduled.map(\.id))
        var failures: [(id: String, message: String)] = []
        for id in installedIdentifiers() where !wanted.contains(id) {
            do { try await remove(id: id) } catch { failures.append((id, Self.describe(error))) }
        }
        for automation in scheduled {
            do {
                let expected = try plistData(for: automation)
                if let existing = try? Data(contentsOf: plistURL(for: automation.id)),
                   Self.sameDictionary(existing, expected) {
                    continue
                }
                try await install(automation)
            } catch {
                failures.append((automation.id, Self.describe(error)))
            }
        }
        if !failures.isEmpty { throw ShellXLaunchAgentSyncError(failures: failures) }
    }

    private static func describe(_ error: any Error) -> String {
        if let e = error as? ShellXLaunchAgentError {
            switch e {
            case let .bootstrapFailed(status, output): return "bootstrap failed (\(status)): \(output)"
            case let .bootoutFailed(status, output): return "bootout failed (\(status)): \(output)"
            case .notScheduled: return "not scheduled"
            case .invalidIdentifier: return "invalid identifier"
            }
        }
        return String(describing: error)
    }

    private static func isNotLoaded(_ result: (status: Int32, output: String)) -> Bool {
        [3, 36, 113].contains(result.status)
            || result.output.contains("No such process")
            || result.output.contains("Could not find service")
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
