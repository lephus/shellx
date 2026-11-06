/// An automation as proposed in the creator, before it is saved.
public struct ShellXAutomationDraft: Codable, Sendable, Equatable {
    /// Kind of automation.
    public var kind: ShellXAutomationKind
    /// Unique kebab-case name.
    public var name: String
    /// Short description.
    public var description: String
    /// Schedule, if any.
    public var schedule: ShellXSchedule?
    /// Directory the run starts in.
    public var workingDirectory: String?
    /// Notification settings.
    public var notify: ShellXNotifySettings
    /// Tools Claude may use unattended.
    public var allowedTools: [String]
    /// Workflow steps.
    public var steps: [ShellXWorkflowStep]
    /// Full `SKILL.md` text including frontmatter.
    public var skillMarkdown: String
    /// Flowchart of the automation, if Claude drew a usable one.
    public var flow: ShellXAutomationFlow?

    /// Creates a draft.
    public init(
        kind: ShellXAutomationKind,
        name: String,
        description: String,
        schedule: ShellXSchedule? = nil,
        workingDirectory: String? = nil,
        notify: ShellXNotifySettings = ShellXNotifySettings(),
        allowedTools: [String] = [],
        steps: [ShellXWorkflowStep] = [],
        skillMarkdown: String,
        flow: ShellXAutomationFlow? = nil
    ) {
        self.kind = kind
        self.name = name
        self.description = description
        self.schedule = schedule
        self.workingDirectory = workingDirectory
        self.notify = notify
        self.allowedTools = allowedTools
        self.steps = steps
        self.skillMarkdown = skillMarkdown
        self.flow = flow
    }
}
