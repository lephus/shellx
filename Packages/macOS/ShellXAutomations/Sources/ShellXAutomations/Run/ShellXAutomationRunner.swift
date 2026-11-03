public import Foundation

/// Runs one automation unattended: takes the run lock, drives `claude`, records the outcome and posts the banner.
public actor ShellXAutomationRunner {
    private static let needsYouMarker = "SHELLX_NEEDS_YOU:"
    private static let promptSuffix = "\n\nYou are running unattended. If you need the user to decide or approve something, stop and end your final message with one line: SHELLX_NEEDS_YOU: <short reason>."

    private let store: ShellXAutomationStore
    private let claude: (any ShellXClaudeLaunching)?
    private let notifier: any ShellXNotifying
    private let pid: Int32
    private let now: @Sendable () -> Date

    /// Creates a runner. `claude` is `nil` when no Claude Code binary was found.
    public init(
        store: ShellXAutomationStore,
        claude: (any ShellXClaudeLaunching)?,
        notifier: any ShellXNotifying,
        pid: Int32,
        now: @escaping @Sendable () -> Date
    ) {
        self.store = store
        self.claude = claude
        self.notifier = notifier
        self.pid = pid
        self.now = now
    }

    /// Runs automation `id` and returns the record. Skipped, unknown and skill runs are not written to disk.
    public func run(id: String, trigger: ShellXRunTrigger) async -> ShellXRunRecord {
        let started = now()
        let automation: ShellXAutomation
        do {
            guard let found = try await store.automation(id: id) else {
                return failure("Unknown automation.", trigger: trigger, started: started)
            }
            automation = found
        } catch {
            return failure(error.localizedDescription, trigger: trigger, started: started)
        }
        if automation.kind == .skill {
            return failure("Skills are run by Claude Code, not on a schedule.", trigger: trigger, started: started)
        }
        let runDirectory: URL
        do {
            guard let begun = try await store.beginRun(id: id, trigger: trigger, pid: pid) else {
                return ShellXRunRecord(status: .skipped, trigger: trigger, startedAt: started, finishedAt: now(), unread: false)
            }
            runDirectory = begun
        } catch {
            return failure(error.localizedDescription, trigger: trigger, started: started)
        }

        var record = await execute(automation, trigger: trigger, started: started, runDirectory: runDirectory)
        record.finishedAt = now()
        record.unread = true
        do {
            try await store.finishRun(id: id, runDirectory: runDirectory, record: record, pid: pid)
        } catch {
            record = ShellXRunRecord(
                status: .failed, trigger: trigger, startedAt: started, finishedAt: now(),
                sessionId: record.sessionId, reason: "ShellX could not save this run: \(error.localizedDescription)"
            )
        }
        await notify(automation, record: record)
        return record
    }
}

// MARK: - Execution

private extension ShellXAutomationRunner {
    func failure(_ message: String, trigger: ShellXRunTrigger, started: Date) -> ShellXRunRecord {
        ShellXRunRecord(status: .failed, trigger: trigger, startedAt: started, finishedAt: now(), reason: message)
    }

    func execute(
        _ automation: ShellXAutomation,
        trigger: ShellXRunTrigger,
        started: Date,
        runDirectory: URL
    ) async -> ShellXRunRecord {
        var record = failure("", trigger: trigger, started: started)
        guard let claude else {
            record.reason = "Claude Code was not found."
            return record
        }
        let prompts: [String]
        if automation.kind == .workflow {
            prompts = automation.steps.map(\.prompt)
        } else {
            let markdown = (try? String(contentsOf: automation.directory.appending(path: "SKILL.md"), encoding: .utf8)) ?? ""
            prompts = [Self.body(ofSkill: markdown)]
        }
        guard !prompts.isEmpty else {
            record.reason = "This workflow has no steps."
            return record
        }
        let workingDirectory = automation.workingDirectory.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? automation.directory
        let transcript = runDirectory.appending(path: "output.jsonl")
        var sessionId: String?
        for (index, prompt) in prompts.enumerated() {
            if automation.kind == .workflow {
                // Cronjobs have a single prompt and leave progress nil; workflows report "step N of M".
                record.currentStep = index + 1
                record.totalSteps = prompts.count
                // try? is deliberate: progress is cosmetic and must never fail the run.
                try? await store.updateRunProgress(
                    id: automation.id, runDirectory: runDirectory, currentStep: index + 1, totalSteps: prompts.count
                )
            }
            let result: ShellXClaudeResult
            do {
                result = try await claude.run(
                    prompt: prompt + Self.promptSuffix,
                    workingDirectory: workingDirectory,
                    allowedTools: automation.allowedTools,
                    resumeSessionId: sessionId,
                    transcript: transcript
                )
            } catch {
                record.reason = error.localizedDescription
                record.sessionId = sessionId
                record.failedStep = automation.kind == .workflow ? index + 1 : nil
                return record
            }
            sessionId = result.sessionId ?? sessionId
            let outcome = Self.outcome(of: result)
            record.status = outcome.status
            record.sessionId = sessionId
            record.summary = outcome.summary
            record.reason = outcome.reason
            if outcome.status != .done {
                record.failedStep = automation.kind == .workflow ? index + 1 : nil
                return record
            }
        }
        return record
    }

    static func outcome(of result: ShellXClaudeResult) -> (status: ShellXRunStatus, summary: String?, reason: String?) {
        let lastErrorLine = result.stderrTail
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        if result.exitCode != 0 {
            return (.failed, nil, lastErrorLine ?? "Claude Code exited with status \(result.exitCode).")
        }
        guard let text = result.resultText else {
            return (.failed, nil, lastErrorLine ?? "Claude Code finished without a result.")
        }
        if result.isError {
            let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (.failed, nil, lastErrorLine ?? (detail.isEmpty ? "Claude Code reported an error." : detail))
        }
        if !result.permissionDenials.isEmpty {
            var tools: [String] = []
            for tool in result.permissionDenials where !tools.contains(tool) { tools.append(tool) }
            return (.needsYou, nil, "Needs permission for: " + tools.joined(separator: ", "))
        }
        var kept: [Substring] = []
        var reason: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(needsYouMarker) {
                reason = String(trimmed.dropFirst(needsYouMarker.count)).trimmingCharacters(in: .whitespaces)
            } else {
                kept.append(line)
            }
        }
        let summary = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason {
            return (.needsYou, summary.isEmpty ? nil : summary, reason.isEmpty ? "Needs your input." : reason)
        }
        return (.done, summary, nil)
    }

    /// `markdown` without its leading `---` frontmatter block, trimmed.
    static func body(ofSkill markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines[(close + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Notification

private extension ShellXAutomationRunner {
    func notify(_ automation: ShellXAutomation, record: ShellXRunRecord) async {
        let event: ShellXNotifyEvent
        let text: String?
        switch record.status {
        case .done: (event, text) = (.done, record.summary)
        case .failed: (event, text) = (.failed, record.reason)
        case .needsYou: (event, text) = (.needsYou, record.reason)
        case .running, .skipped: return
        }
        guard automation.notify.on.contains(event), automation.notify.targets.contains(.mac) else { return }
        try? await notifier.post(ShellXAutomationNotification(name: automation.name, body: text ?? "", automationId: automation.id))
    }
}
