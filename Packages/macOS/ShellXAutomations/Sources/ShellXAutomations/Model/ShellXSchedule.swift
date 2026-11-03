/// A cron schedule with its human-readable description.
public struct ShellXSchedule: Codable, Sendable, Equatable {
    /// Five-field cron expression.
    public var cron: String
    /// Human-readable description shown in the UI.
    public var human: String

    /// Creates a schedule.
    public init(cron: String, human: String) {
        self.cron = cron
        self.human = human
    }
}
