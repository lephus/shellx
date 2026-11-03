/// A run outcome a user can be notified about.
public enum ShellXNotifyEvent: String, Codable, Sendable, Equatable, CaseIterable {
    /// `done,failed,needsYou`.
    case done,failed,needsYou
}
