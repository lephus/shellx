/// The kind of automation a user can create.
public enum ShellXAutomationKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// `skill,workflow,cronjob`.
    case skill,workflow,cronjob
}
