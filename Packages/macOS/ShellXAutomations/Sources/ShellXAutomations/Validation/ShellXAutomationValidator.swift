/// Checks an automation draft before anything is written to disk.
public struct ShellXAutomationValidator: Sendable {
    private let existingNames: Set<String>
    private let directoryExists: @Sendable (String) -> Bool
    private let claudeAvailable: Bool

    /// Creates a validator.
    /// - Parameters:
    ///   - existingNames: Names of skills and automations that already exist.
    ///   - directoryExists: Answers whether a directory path exists.
    ///   - claudeAvailable: Whether the `claude` executable was found.
    public init(existingNames: Set<String>, directoryExists: @escaping @Sendable (String) -> Bool, claudeAvailable: Bool) {
        self.existingNames = existingNames
        self.directoryExists = directoryExists
        self.claudeAvailable = claudeAvailable
    }

    /// Returns every problem with `draft`; empty means valid.
    /// - Parameter replacingName: The draft's current name when editing, so it does not collide with itself.
    public func validate(_ draft: ShellXAutomationDraft, replacingName: String?) -> [ShellXValidationIssue] {
        var issues: [ShellXValidationIssue] = []
        issues += nameIssues(draft, replacingName: replacingName)
        if draft.description.isEmpty {
            issues.append(.init(field: .description, code: "missing", message: "Description is required."))
        } else if draft.description.count > 1024 {
            issues.append(.init(field: .description, code: "tooLong", message: "Description must be at most 1024 characters."))
        }
        issues += scheduleIssues(draft)
        if draft.kind != .skill {
            issues += directoryIssues(draft)
            if !claudeAvailable {
                issues.append(.init(field: .claude, code: "unavailable", message: "Claude Code was not found on this Mac."))
            }
        }
        issues += stepIssues(draft)
        issues += markdownIssues(draft)
        return issues
    }

    /// A workflow runs its steps in order, so it needs at least one, each with a prompt.
    private func stepIssues(_ draft: ShellXAutomationDraft) -> [ShellXValidationIssue] {
        guard draft.kind == .workflow else { return [] }
        if draft.steps.isEmpty {
            return [.init(field: .steps, code: "missing", message: "A workflow needs at least one step.")]
        }
        if draft.steps.contains(where: { $0.prompt.allSatisfy(\.isWhitespace) }) {
            return [.init(field: .steps, code: "emptyPrompt", message: "Every step needs a prompt.")]
        }
        return []
    }

    private func nameIssues(_ draft: ShellXAutomationDraft, replacingName: String?) -> [ShellXValidationIssue] {
        let name = draft.name
        if name.isEmpty {
            return [.init(field: .name, code: "missing", message: "Name is required.")]
        }
        if name.count > 64 {
            return [.init(field: .name, code: "tooLong", message: "Name must be at most 64 characters.")]
        }
        if name.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) == nil {
            return [.init(field: .name, code: "invalid", message: "Name may only use lowercase letters, digits and single hyphens.")]
        }
        if existingNames.contains(name) && name != replacingName {
            return [.init(field: .name, code: "duplicate", message: "A skill or automation named \"\(name)\" already exists.")]
        }
        return []
    }

    private func scheduleIssues(_ draft: ShellXAutomationDraft) -> [ShellXValidationIssue] {
        guard draft.kind != .skill else { return [] }
        guard let schedule = draft.schedule else {
            return draft.kind == .cronjob
                ? [.init(field: .schedule, code: "missing", message: "A cronjob needs a schedule.")]
                : []
        }
        do {
            _ = try ShellXCronExpression(schedule.cron).launchdCalendarIntervals()
            return []
        } catch {
            return [.init(field: .schedule, code: "invalid", message: "This schedule cannot be set up on the Mac: \(error.description).")]
        }
    }

    private func directoryIssues(_ draft: ShellXAutomationDraft) -> [ShellXValidationIssue] {
        guard let path = draft.workingDirectory, !path.isEmpty else {
            return [.init(field: .workingDirectory, code: "missing", message: "A working folder is required.")]
        }
        return directoryExists(path)
            ? []
            : [.init(field: .workingDirectory, code: "notFound", message: "The folder \(path) does not exist.")]
    }

    private func markdownIssues(_ draft: ShellXAutomationDraft) -> [ShellXValidationIssue] {
        do {
            let frontmatter = try ShellXSkillFrontmatter(markdown: draft.skillMarkdown)
            var issues: [ShellXValidationIssue] = []
            if frontmatter.name != draft.name {
                issues.append(.init(field: .skillMarkdown, code: "mismatch", message: "The SKILL.md name must equal the automation name."))
            }
            if frontmatter.description.isEmpty {
                issues.append(.init(field: .skillMarkdown, code: "missing", message: "The SKILL.md description is required."))
            }
            return issues
        } catch {
            return [.init(field: .skillMarkdown, code: "invalid", message: "SKILL.md needs frontmatter with a name and description.")]
        }
    }
}
