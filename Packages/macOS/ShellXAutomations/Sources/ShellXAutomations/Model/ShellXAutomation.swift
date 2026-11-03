public import Foundation

/// A saved automation. `directory` and `lastRun` are not part of `automation.json`.
public struct ShellXAutomation: Codable, Sendable, Equatable, Identifiable {
    /// Stable identifier.
    public let id: String
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
    /// Whether the schedule is active.
    public var enabled: Bool
    /// Who created it.
    public var origin: ShellXAutomationOrigin
    /// Creation time.
    public var createdAt: Date
    /// Last modification time.
    public var updatedAt: Date
    /// Folder holding the automation's files; assigned by the store, never encoded.
    public var directory: URL
    /// Most recent run; assigned by the store, never encoded.
    public var lastRun: ShellXRunRecord?

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, description, schedule, workingDirectory, notify
        case allowedTools, steps, enabled, origin, createdAt, updatedAt
    }

    /// Creates an automation.
    public init(
        id: String,
        kind: ShellXAutomationKind,
        name: String,
        description: String,
        schedule: ShellXSchedule? = nil,
        workingDirectory: String? = nil,
        notify: ShellXNotifySettings = ShellXNotifySettings(),
        allowedTools: [String] = [],
        steps: [ShellXWorkflowStep] = [],
        enabled: Bool = true,
        origin: ShellXAutomationOrigin = .shellx,
        createdAt: Date,
        updatedAt: Date,
        directory: URL,
        lastRun: ShellXRunRecord? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.description = description
        self.schedule = schedule
        self.workingDirectory = workingDirectory
        self.notify = notify
        self.allowedTools = allowedTools
        self.steps = steps
        self.enabled = enabled
        self.origin = origin
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.directory = directory
        self.lastRun = lastRun
    }

    /// Decodes `automation.json`; `directory` is a placeholder (`/`) the store must replace.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            kind: try c.decode(ShellXAutomationKind.self, forKey: .kind),
            name: try c.decode(String.self, forKey: .name),
            description: try c.decode(String.self, forKey: .description),
            schedule: try c.decodeIfPresent(ShellXSchedule.self, forKey: .schedule),
            workingDirectory: try c.decodeIfPresent(String.self, forKey: .workingDirectory),
            notify: try c.decode(ShellXNotifySettings.self, forKey: .notify),
            allowedTools: try c.decode([String].self, forKey: .allowedTools),
            steps: try c.decode([ShellXWorkflowStep].self, forKey: .steps),
            enabled: try c.decode(Bool.self, forKey: .enabled),
            origin: try c.decode(ShellXAutomationOrigin.self, forKey: .origin),
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            updatedAt: try c.decode(Date.self, forKey: .updatedAt),
            directory: URL(filePath: "/")
        )
    }

    /// Encodes `automation.json` without `directory` and `lastRun`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(schedule, forKey: .schedule)
        try c.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        try c.encode(notify, forKey: .notify)
        try c.encode(allowedTools, forKey: .allowedTools)
        try c.encode(steps, forKey: .steps)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(origin, forKey: .origin)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
