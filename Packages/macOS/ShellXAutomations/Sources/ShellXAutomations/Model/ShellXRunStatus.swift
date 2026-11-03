/// The state of one automation run.
public enum ShellXRunStatus: String, Codable, Sendable, Equatable, CaseIterable {
    /// `running,done,failed,needsYou,skipped`.
    case running,done,failed,needsYou,skipped
}
