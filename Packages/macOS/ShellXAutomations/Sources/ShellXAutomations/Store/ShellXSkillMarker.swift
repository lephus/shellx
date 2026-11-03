public import Foundation

/// The `.shellx.json` file next to a ShellX-made skill's `SKILL.md`.
public struct ShellXSkillMarker: Codable, Sendable, Equatable {
    /// Stable automation id (UUID string).
    public let id: String
    /// Notification settings.
    public var notify: ShellXNotifySettings
    /// Creation time.
    public var createdAt: Date
    /// Last modification time.
    public var updatedAt: Date
    /// Bundle that wrote the skill.
    public let bundleIdentifier: String

    /// Creates a marker.
    public init(id: String, notify: ShellXNotifySettings, createdAt: Date, updatedAt: Date, bundleIdentifier: String) {
        self.id = id
        self.notify = notify
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bundleIdentifier = bundleIdentifier
    }
}
