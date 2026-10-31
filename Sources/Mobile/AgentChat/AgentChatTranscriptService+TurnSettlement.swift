import CmuxAgentChat
import Foundation

extension AgentChatTranscriptService {
    /// Settles the turns an agent on `surfaceID` ended without a hook.
    ///
    /// - Parameters:
    ///   - surfaceID: The terminal surface whose agent reported the end of its activity.
    ///   - agentKind: The agent that reported it.
    ///   - edge: When the agent's activity report ended.
    /// - Returns: How many sessions left working or needs-input.
    @discardableResult
    func noteTurnSettled(surfaceID: String, agentKind: ChatAgentKind, at edge: Date) -> Int {
        0
    }
}
