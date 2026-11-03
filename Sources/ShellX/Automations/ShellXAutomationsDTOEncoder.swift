import Foundation
import ShellXAutomations

/// Turns package values into the JSON objects the Automations page reads
/// (`AutomationDTO`, `AutomationDraft`, `ValidationIssueDTO` and `CreatorEvent` in `types.ts`).
struct ShellXAutomationsDTOEncoder {
    private let calendar: Calendar
    private let now: () -> Date
    private let issueMessages: ShellXAutomationsIssueMessages

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        issueMessages: ShellXAutomationsIssueMessages = ShellXAutomationsIssueMessages()
    ) {
        self.calendar = calendar
        self.now = now
        self.issueMessages = issueMessages
    }

    func automation(_ automation: ShellXAutomation) -> [String: Any] {
        var object: [String: Any] = [
            "id": automation.id,
            "kind": automation.kind.rawValue,
            "name": automation.name,
            "description": automation.description,
            "notify": notify(automation.notify),
            "allowedTools": automation.allowedTools,
            "steps": automation.steps.map(step),
            "enabled": automation.enabled,
            "origin": automation.origin.rawValue,
            "createdAt": date(automation.createdAt),
            "updatedAt": date(automation.updatedAt),
            "iphonePending": automation.notify.targets.contains(.iphone),
        ]
        if let schedule = automation.schedule {
            object["schedule"] = ["cron": schedule.cron, "human": schedule.human]
            if automation.kind != .skill, automation.enabled,
               let expression = try? ShellXCronExpression(schedule.cron),
               let next = expression.nextFireDate(after: now(), calendar: calendar) {
                object["nextRun"] = date(next)
            }
        }
        if let workingDirectory = automation.workingDirectory {
            object["workingDirectory"] = workingDirectory
        }
        if let run = automation.lastRun {
            object["lastRun"] = self.run(run)
        }
        return object
    }

    func run(_ run: ShellXRunRecord) -> [String: Any] {
        var object: [String: Any] = [
            "status": run.status.rawValue,
            "trigger": run.trigger.rawValue,
            "startedAt": date(run.startedAt),
            "unread": run.unread,
        ]
        if let finishedAt = run.finishedAt { object["finishedAt"] = date(finishedAt) }
        if let sessionId = run.sessionId { object["sessionId"] = sessionId }
        if let summary = run.summary { object["summary"] = summary }
        if let reason = run.reason { object["reason"] = reason }
        if let failedStep = run.failedStep { object["failedStep"] = failedStep }
        return object
    }

    func draft(_ draft: ShellXAutomationDraft) -> [String: Any] {
        [
            "kind": draft.kind.rawValue,
            "name": draft.name,
            "description": draft.description,
            "schedule": draft.schedule.map { ["cron": $0.cron, "human": $0.human] as Any } ?? NSNull(),
            "workingDirectory": draft.workingDirectory ?? NSNull(),
            "notify": notify(draft.notify),
            "allowedTools": draft.allowedTools,
            "steps": draft.steps.map(step),
            "skillMarkdown": draft.skillMarkdown,
        ]
    }

    /// Issues for the page, with a localized message for every known field and code.
    func issues(_ issues: [ShellXValidationIssue], draft: ShellXAutomationDraft) -> [[String: Any]] {
        issues.map { issue in
            [
                "field": issue.field.rawValue,
                "code": issue.code,
                "message": issueMessages.message(for: issue, draft: draft),
            ]
        }
    }

    /// The `CreatorEvent` object for a session event.
    func creatorEvent(_ event: ShellXCreatorEvent) -> [String: Any] {
        switch event {
        case .textDelta(let text):
            return ["type": "textDelta", "text": text]
        case .assistantMessage(let text, let choices):
            var object: [String: Any] = ["type": "assistantMessage", "text": text]
            if let choices {
                object["choices"] = ["question": choices.question, "multi": choices.multi, "options": choices.options]
            }
            return object
        case .draft(let draft):
            return ["type": "draft", "draft": self.draft(draft)]
        case .busy(let busy):
            return ["type": "busy", "busy": busy]
        case .failed(let message):
            return ["type": "failed", "message": message]
        }
    }

    /// A `ShellXAutomationDraft` that reproduces a saved automation, for editing.
    func draft(from automation: ShellXAutomation, skillMarkdown: String) -> ShellXAutomationDraft {
        ShellXAutomationDraft(
            kind: automation.kind,
            name: automation.name,
            description: automation.description,
            schedule: automation.schedule,
            workingDirectory: automation.workingDirectory,
            notify: automation.notify,
            allowedTools: automation.allowedTools,
            steps: automation.steps,
            skillMarkdown: skillMarkdown
        )
    }

    private func notify(_ settings: ShellXNotifySettings) -> [String: Any] {
        ["on": settings.on.map(\.rawValue), "targets": settings.targets.map(\.rawValue)]
    }

    private func step(_ step: ShellXWorkflowStep) -> [String: Any] {
        ["title": step.title, "prompt": step.prompt]
    }

    private func date(_ date: Date) -> String {
        date.ISO8601Format()
    }
}
