import Foundation

extension ChatMessage {
    /// Whether this is the line Claude Code writes when the user stops a turn.
    public var isUserInterruptMarker: Bool {
        false
    }

    /// When the user stopped the turn that ends `messages`.
    ///
    /// - Parameter messages: Transcript messages in ascending seq.
    /// - Returns: The interrupt marker's time, or `nil`.
    public static func trailingUserInterrupt(in messages: [ChatMessage]) -> Date? {
        nil
    }
}
