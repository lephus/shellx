import Darwin
import Foundation
import ShellXAutomations

/// `shellx routine run|notify|list`: the one run path for scheduled automations, "Run now" and skills.
/// Works without the app or its socket; everything is derived from the app bundle this CLI ships in.
extension CMUXCLI {
    static func routineUsage() -> String {
        String(
            localized: "cli.routine.help",
            defaultValue: """
        Usage: shellx routine <run|notify|list> [args]

        Runs and reports ShellX automations (cronjobs and workflows) without the app.
          shellx routine run <id> [--trigger schedule|manual]
          shellx routine notify --name <name> --status done|failed|needs-you --body <text>
          shellx routine list [--json]

        notify reports only that ShellX Notifier was launched; macOS shows the banner.
        """
        )
    }

    func runRoutineCommand(commandArgs: [String], jsonOutput: Bool) async throws {
        let command: ShellXRoutineCommand
        do {
            command = try ShellXRoutineArguments(commandArgs).command
        } catch let error as ShellXRoutineArgumentsError {
            throw CLIError(message: routineArgumentsMessage(error))
        } catch {
            throw error
        }
        guard let executable = CLIExecutableLocator.currentExecutableURL(),
              let layout = ShellXRoutineBundleLayout(cliPath: executable.path) else {
            throw CLIError(message: String(
                localized: "cli.routine.error.notInBundle",
                defaultValue: "shellx routine only runs from the shellx inside an app bundle (ShellX.app/Contents/Resources/bin/shellx)."
            ))
        }
        guard let bundleIdentifier = Bundle(path: layout.appPath)?.bundleIdentifier, !bundleIdentifier.isEmpty else {
            throw CLIError(message: String(
                format: String(localized: "cli.routine.error.bundleID", defaultValue: "Could not read the bundle identifier from %@."),
                layout.infoPlistPath
            ))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ShellXAutomationEnvironment(
            bundleIdentifier: bundleIdentifier,
            home: home,
            cliPath: layout.cliPath,
            notifierAppPath: layout.notifierAppPath
        )
        let store = ShellXAutomationStore(environment: environment, trasher: ShellXFileManagerTrasher(), now: { Date() })
        let notifier = ShellXNotifierClient(helperAppPath: layout.notifierAppPath) { argv in
            try await ShellXArgvProcess().run(argv)
        }

        switch command {
        case .run(let id, let trigger):
            try await runRoutine(id: id, trigger: trigger, store: store, notifier: notifier, home: home, jsonOutput: jsonOutput)
        case .notify(let name, _, let body):
            let automationId = (try? await store.automation(named: name))?.id
            do {
                try await notifier.post(ShellXAutomationNotification(name: name, body: body, automationId: automationId))
            } catch ShellXNotifierError.openFailed(let status) {
                throw CLIError(message: String(
                    format: String(
                        localized: "cli.routine.error.notifierFailed",
                        defaultValue: "Could not launch ShellX Notifier (open exited with status %d)."
                    ),
                    Int(status)
                ))
            }
            if jsonOutput { print(jsonString(["launched": true])) }
        case .list(let json):
            try await printRoutineList(store: store, jsonOutput: json || jsonOutput)
        }
    }

    private func runRoutine(
        id: String,
        trigger: ShellXRunTrigger,
        store: ShellXAutomationStore,
        notifier: ShellXNotifierClient,
        home: URL,
        jsonOutput: Bool
    ) async throws {
        let processEnvironment = ProcessInfo.processInfo.environment
        let resolver = ShellXClaudeExecutableResolver(
            environment: processEnvironment,
            home: home,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
            loginShellLookup: { ShellXLoginShellClaudeLookup()() }
        )
        let claudeEnvironment = ShellXRoutineClaudeEnvironment.live(inherited: processEnvironment, home: home)
        // Both lookups may block on a login shell for seconds; keep them off the cooperative pool.
        let launch: (path: String, environment: [String: String])? = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let found = resolver.resolve().map { path in (path, claudeEnvironment.environment(forClaudeAt: path)) }
                continuation.resume(returning: found)
            }
        }
        let claude = launch.map { ShellXClaudeProcess(executable: $0.path, environment: $0.environment) }
        let runner = ShellXAutomationRunner(store: store, claude: claude, notifier: notifier, pid: getpid(), now: { Date() })
        let record = await runner.run(id: id, trigger: trigger)
        let status = Self.routineStatusToken(record.status)
        if jsonOutput {
            var object: [String: Any] = ["id": id, "status": status, "trigger": record.trigger.rawValue]
            if let summary = record.summary { object["summary"] = summary }
            if let reason = record.reason { object["reason"] = reason }
            if let sessionId = record.sessionId { object["sessionId"] = sessionId }
            if let failedStep = record.failedStep { object["failedStep"] = failedStep }
            print(jsonString(object))
        } else if let detail = record.reason ?? record.summary, !detail.isEmpty {
            print("\(status): \(detail)")
        } else {
            print(status)
        }
        if record.status == .failed { Darwin.exit(1) }
    }

    private func printRoutineList(store: ShellXAutomationStore, jsonOutput: Bool) async throws {
        let automations = try await store.list()
        if jsonOutput {
            let rows: [[String: Any]] = automations.map { automation in
                [
                    "id": automation.id,
                    "name": automation.name,
                    "kind": automation.kind.rawValue,
                    "enabled": automation.enabled,
                    "lastStatus": automation.lastRun.map { Self.routineStatusToken($0.status) } ?? NSNull(),
                ]
            }
            print(jsonString(rows))
            return
        }
        guard !automations.isEmpty else {
            print(String(localized: "cli.routine.list.empty", defaultValue: "No automations"))
            return
        }
        let header = [
            String(localized: "cli.routine.list.name", defaultValue: "NAME"),
            String(localized: "cli.routine.list.kind", defaultValue: "KIND"),
            String(localized: "cli.routine.list.enabled", defaultValue: "ENABLED"),
            String(localized: "cli.routine.list.lastRun", defaultValue: "LAST RUN"),
        ]
        let rows = automations.map { automation in
            [
                automation.name,
                automation.kind.rawValue,
                automation.enabled ? "true" : "false",
                automation.lastRun.map { Self.routineStatusToken($0.status) } ?? "-",
            ]
        }
        let table = [header] + rows
        let widths = header.indices.map { column in table.map { $0[column].count }.max() ?? 0 }
        for row in table {
            let cells = row.enumerated().map { column, cell in
                column == row.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }
            print(cells.joined(separator: "  "))
        }
    }

    /// The CLI spelling of a run status (`needs-you`, as `routine notify --status` takes it).
    private static func routineStatusToken(_ status: ShellXRunStatus) -> String {
        status == .needsYou ? "needs-you" : status.rawValue
    }

    private func routineArgumentsMessage(_ error: ShellXRoutineArgumentsError) -> String {
        let detail: String?
        switch error {
        case .usage:
            detail = nil
        case .unknownSubcommand(let name):
            detail = String(
                format: String(localized: "cli.routine.error.unknownSubcommand", defaultValue: "Unknown routine subcommand: %@"),
                name
            )
        case .missingID:
            detail = String(localized: "cli.routine.error.missingID", defaultValue: "routine run needs an automation id.")
        case .missingValue(let flag):
            detail = String(format: String(localized: "cli.routine.error.missingValue", defaultValue: "%@ needs a value."), flag)
        case .invalidTrigger(let value):
            detail = String(
                format: String(localized: "cli.routine.error.invalidTrigger", defaultValue: "--trigger must be schedule or manual, not %@."),
                value
            )
        case .invalidStatus(let value):
            detail = String(
                format: String(localized: "cli.routine.error.invalidStatus", defaultValue: "--status must be done, failed or needs-you, not %@."),
                value
            )
        case .unexpectedArgument(let value):
            detail = String(
                format: String(localized: "cli.routine.error.unexpectedArgument", defaultValue: "Unexpected argument: %@"),
                value
            )
        }
        guard let detail else { return Self.routineUsage() }
        return detail + "\n\n" + Self.routineUsage()
    }
}
