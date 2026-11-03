/// What started a run.
public enum ShellXRunTrigger: String, Codable, Sendable, Equatable, CaseIterable {
    /// `schedule,manual`.
    case schedule,manual
}
