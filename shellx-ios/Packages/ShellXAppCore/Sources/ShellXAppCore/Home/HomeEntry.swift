import Foundation

/// One line of the home conversation: what the user said or typed, or a ShellX note. Kept on the
/// phone (`StoreDocument.home`).
public struct HomeEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Content: Codable, Equatable, Sendable {
        /// A message the user sent (or tried to send) and the session it went to; nil when none was
        /// running.
        case userSaid(text: String, target: SessionRef?, viaVoice: Bool)
        /// A canned line from ShellX: what became of a message, or a session that finished.
        case note(HomeNote)
    }

    public var id: String
    public var at: Date
    public var content: Content

    public init(id: String, at: Date, content: Content) {
        self.id = id
        self.at = at
        self.content = content
    }
}
