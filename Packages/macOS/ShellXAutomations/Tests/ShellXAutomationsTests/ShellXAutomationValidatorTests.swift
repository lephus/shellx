import Testing
@testable import ShellXAutomations

struct ShellXAutomationValidatorTests {
    private func markdown(_ name: String, _ description: String = "Does things") -> String {
        "---\nname: \(name)\ndescription: \(description)\n---\nBody"
    }

    private func draft(
        kind: ShellXAutomationKind = .skill,
        name: String = "pr-digest",
        description: String = "Does things",
        schedule: ShellXSchedule? = nil,
        workingDirectory: String? = nil,
        markdownName: String? = nil
    ) -> ShellXAutomationDraft {
        ShellXAutomationDraft(
            kind: kind, name: name, description: description, schedule: schedule,
            workingDirectory: workingDirectory, skillMarkdown: markdown(markdownName ?? name)
        )
    }

    private func validator(existing: Set<String> = [], claude: Bool = true, dirs: Set<String> = ["/work"]) -> ShellXAutomationValidator {
        ShellXAutomationValidator(existingNames: existing, directoryExists: { dirs.contains($0) }, claudeAvailable: claude)
    }

    @Test func validSkillHasNoIssues() {
        #expect(validator().validate(draft(), replacingName: nil).isEmpty)
    }

    @Test(arguments: ["../x", "My Skill", "a--b", String(repeating: "a", count: 65), ""])
    func rejectsBadNames(_ name: String) {
        let issues = validator().validate(draft(name: name, markdownName: name), replacingName: nil)
        #expect(issues.contains { $0.field == .name })
    }

    @Test func rejectsDuplicateName() {
        let v = validator(existing: ["pr-digest"])
        #expect(v.validate(draft(), replacingName: nil).contains { $0.field == .name && $0.code == "duplicate" })
        #expect(v.validate(draft(), replacingName: "pr-digest").isEmpty)
    }

    @Test func cronjobNeedsScheduleAndDirectory() {
        let issues = validator().validate(draft(kind: .cronjob), replacingName: nil)
        #expect(issues.contains { $0.field == .schedule })
        #expect(issues.contains { $0.field == .workingDirectory })
    }

    @Test func workflowScheduleIsOptional() {
        let issues = validator().validate(draft(kind: .workflow, workingDirectory: "/work"), replacingName: nil)
        #expect(issues.isEmpty)
    }

    @Test func missingDirectoryIsNotFound() {
        let issues = validator().validate(draft(kind: .workflow, workingDirectory: "/nope"), replacingName: nil)
        #expect(issues.contains { $0.field == .workingDirectory && $0.code == "notFound" })
    }

    @Test func unschedulableCronIsRejected() {
        let d = draft(kind: .cronjob, schedule: ShellXSchedule(cron: "*/7 */1 * * *", human: "x"), workingDirectory: "/work")
        #expect(validator().validate(d, replacingName: nil).contains { $0.field == .schedule && $0.code == "invalid" })
    }

    @Test func validCronjobHasNoIssues() {
        let d = draft(kind: .cronjob, schedule: ShellXSchedule(cron: "0 8 * * *", human: "x"), workingDirectory: "/work")
        #expect(validator().validate(d, replacingName: nil).isEmpty)
    }

    @Test func skillMarkdownMustMatchName() {
        let issues = validator().validate(draft(markdownName: "other"), replacingName: nil)
        #expect(issues.contains { $0.field == .skillMarkdown && $0.code == "mismatch" })
    }

    @Test func brokenFrontmatterIsInvalid() {
        var d = draft()
        d.skillMarkdown = "no frontmatter"
        #expect(validator().validate(d, replacingName: nil).contains { $0.field == .skillMarkdown && $0.code == "invalid" })
    }

    @Test func claudeMissing() {
        let v = validator(claude: false)
        let cron = draft(kind: .cronjob, schedule: ShellXSchedule(cron: "0 8 * * *", human: "x"), workingDirectory: "/work")
        #expect(v.validate(cron, replacingName: nil).contains { $0.field == .claude })
        #expect(!v.validate(draft(), replacingName: nil).contains { $0.field == .claude })
    }

    @Test func descriptionTooLong() {
        let d = draft(description: String(repeating: "a", count: 1025))
        #expect(validator().validate(d, replacingName: nil).contains { $0.field == .description && $0.code == "tooLong" })
    }
}
