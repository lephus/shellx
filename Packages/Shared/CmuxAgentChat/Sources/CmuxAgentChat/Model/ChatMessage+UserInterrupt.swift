import Foundation

extension ChatMessage {
    /// The start of the user line Claude Code writes when the user stops a
    /// turn (Esc or ctrl-C): `[Request interrupted by user]`, or
    /// `[Request interrupted by user for tool use]` when they rejected a tool
    /// prompt. Claude Code runs no hook for it and then waits at its prompt.
    private static let userInterruptMarkerPrefix = "[Request interrupted by user"

    /// Whether this is the line Claude Code writes when the user stops a turn.
    ///
    /// The whole prose must be the one bracketed marker, so a prompt that only
    /// quotes it does not count.
    public var isUserInterruptMarker: Bool {
        guard role == .user, case .prose(let prose) = kind else { return false }
        let text = prose.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(Self.userInterruptMarkerPrefix) else { return false }
        return text.firstIndex(of: "]") == text.index(before: text.endIndex)
    }

    /// When the user stopped the turn that ends `messages`: the time of an
    /// interrupt marker that nothing the user or the agent wrote follows.
    /// Status transitions and system lines do not count as conversation.
    ///
    /// - Parameter messages: Transcript messages in ascending seq.
    /// - Returns: The interrupt marker's time, or `nil`.
    public static func trailingUserInterrupt(in messages: [ChatMessage]) -> Date? {
        let last = messages.last(where: { message in
            if case .status = message.kind { return false }
            return message.role != .system
        })
        guard let last, last.isUserInterruptMarker else { return nil }
        return last.timestamp
    }
}
