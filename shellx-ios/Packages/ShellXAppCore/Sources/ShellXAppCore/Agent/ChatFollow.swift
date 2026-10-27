import Foundation

/// Whether an agent's chat follows its newest entry. It does only while the bottom of the chat is
/// on screen. Otherwise the user is reading older entries: the chat stays where it is, and
/// `hasUnseen` asks the screen to offer "New messages ↓".
public struct ChatFollow: Equatable, Sendable {
    /// The bottom of the chat is on screen (true until the screen says otherwise).
    public private(set) var atBottom = true
    /// Newer entries came while the user read older ones.
    public private(set) var hasUnseen = false
    private var newestID: String?

    public init() {}

    /// The bottom of the chat came into view (the user scrolled down to it) or left it.
    public mutating func bottomVisible(_ visible: Bool) {
        atBottom = visible
        if visible { hasUnseen = false }
    }

    /// The chat's newest entry is now `id`. Returns true when the chat should scroll to it; a new
    /// entry while the user reads older ones only sets `hasUnseen`. The same newest entry (an older
    /// page came in above, an entry grew in place) changes nothing.
    public mutating func newest(_ id: String?) -> Bool {
        guard id != newestID else { return false }
        newestID = id
        guard id != nil else {
            hasUnseen = false
            return false
        }
        if atBottom { return true }
        hasUnseen = true
        return false
    }

    /// The user tapped "New messages": the chat scrolls to the bottom.
    public mutating func jumpedToBottom() {
        atBottom = true
        hasUnseen = false
    }
}
