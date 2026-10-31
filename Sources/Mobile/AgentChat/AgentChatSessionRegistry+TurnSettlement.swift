import CmuxAgentChat
import Foundation

extension AgentChatSessionRegistry {
    /// Settles the turns an agent on one terminal ended without a hook.
    ///
    /// - Parameters:
    ///   - surfaceID: The terminal surface whose agent reported the end of its activity.
    ///   - agentKind: The agent that reported it.
    ///   - edge: When the agent's activity report ended.
    /// - Returns: The sessions that left working or needs-input.
    @discardableResult
    func noteTurnSettled(surfaceID: String, agentKind: ChatAgentKind, at edge: Date) -> [String] {
        []
    }

    /// Settles a Claude turn its transcript says the user interrupted.
    ///
    /// - Parameters:
    ///   - sessionID: The session whose transcript holds the marker.
    ///   - marker: The interrupt marker's transcript time.
    /// - Returns: Whether the session left working or needs-input.
    @discardableResult
    func noteTranscriptInterrupt(sessionID: String, at marker: Date) -> Bool {
        false
    }
}
