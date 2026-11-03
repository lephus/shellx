/// Which run outcomes notify the user, and where.
public struct ShellXNotifySettings: Codable, Sendable, Equatable {
    /// Outcomes that trigger a notification.
    public var on: [ShellXNotifyEvent]
    /// Delivery targets.
    public var targets: [ShellXNotifyTarget]

    /// Creates notification settings.
    public init(on: [ShellXNotifyEvent] = [.done, .failed, .needsYou], targets: [ShellXNotifyTarget] = [.mac]) {
        self.on = on
        self.targets = targets
    }
}
