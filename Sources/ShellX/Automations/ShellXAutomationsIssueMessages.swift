import Foundation
import ShellXAutomations

/// Localized text for the validator's issues, chosen by field and code.
///
/// The validator's own `message` is plain English; it is the fallback for a code this
/// table does not know, and it is what the creator sends back to the model.
struct ShellXAutomationsIssueMessages {
    func message(for issue: ShellXValidationIssue, draft: ShellXAutomationDraft) -> String {
        switch (issue.field, issue.code) {
        case (.name, "missing"):
            return String(localized: "automations.issue.name.missing", defaultValue: "Name is required.")
        case (.name, "tooLong"):
            return String(localized: "automations.issue.name.tooLong", defaultValue: "Name must be at most 64 characters.")
        case (.name, "invalid"):
            return String(
                localized: "automations.issue.name.invalid",
                defaultValue: "Name may only use lowercase letters, digits and single hyphens."
            )
        case (.name, "duplicate"):
            return String(
                localized: "automations.issue.name.duplicate",
                defaultValue: "A skill or automation with this name already exists."
            )
        case (.description, "missing"):
            return String(localized: "automations.issue.description.missing", defaultValue: "Description is required.")
        case (.description, "tooLong"):
            return String(
                localized: "automations.issue.description.tooLong",
                defaultValue: "Description must be at most 1024 characters."
            )
        case (.schedule, "missing"):
            return String(localized: "automations.issue.schedule.missing", defaultValue: "A cronjob needs a schedule.")
        case (.schedule, "invalid"):
            return String(
                localized: "automations.issue.schedule.invalid",
                defaultValue: "This schedule cannot be set up on the Mac."
            )
        case (.workingDirectory, "missing"):
            return String(localized: "automations.issue.directory.missing", defaultValue: "A working folder is required.")
        case (.workingDirectory, "notFound"):
            let path = draft.workingDirectory ?? ""
            return String(localized: "automations.issue.directory.notFound", defaultValue: "The folder \(path) does not exist.")
        case (.skillMarkdown, "mismatch"):
            return String(
                localized: "automations.issue.skill.mismatch",
                defaultValue: "The SKILL.md name must equal the automation name."
            )
        case (.skillMarkdown, "missing"):
            return String(localized: "automations.issue.skill.missing", defaultValue: "The SKILL.md description is required.")
        case (.skillMarkdown, "invalid"):
            return String(
                localized: "automations.issue.skill.invalid",
                defaultValue: "SKILL.md needs frontmatter with a name and description."
            )
        case (.steps, "missing"):
            return String(localized: "automations.issue.steps.missing", defaultValue: "A workflow needs at least one step.")
        case (.steps, "emptyPrompt"):
            return String(localized: "automations.issue.steps.emptyPrompt", defaultValue: "Every step needs a prompt.")
        case (.kind, "mustStaySkill"):
            return String(
                localized: "automations.issue.kind.mustStaySkill",
                defaultValue: "ShellX did not create this skill, so it must stay a skill."
            )
        case (.claude, "unavailable"):
            return String(localized: "automations.issue.claude.unavailable", defaultValue: "Claude Code was not found on this Mac.")
        default:
            return issue.message
        }
    }
}
