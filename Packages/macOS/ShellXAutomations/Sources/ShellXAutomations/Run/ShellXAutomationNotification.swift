public import Foundation

/// A banner for a finished automation run.
public struct ShellXAutomationNotification: Sendable, Equatable {
    /// Banner title: the automation name.
    public let title: String
    /// Banner body, at most 181 characters.
    public let body: String
    /// Link opened by a click.
    public let url: URL
    /// Grouping key: the automation id.
    public let group: String

    /// Creates a notification.
    public init(title: String, body: String, url: URL, group: String) {
        self.title = title
        self.body = body
        self.url = url
        self.group = group
    }
}
