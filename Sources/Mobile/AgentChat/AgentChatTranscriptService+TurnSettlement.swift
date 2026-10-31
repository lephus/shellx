import CmuxAgentChat
import Foundation

/// Turns an agent ended without a hook (see the registry's turn settlement).
/// The registry settles them, and the turn's live prose preview ends with
/// them, as for the phone's own interrupt.
extension AgentChatTranscriptService {
    /// How many of the newest messages a tailer that just loaded an existing
    /// transcript checks for Claude Code's user-interrupt marker.
    static let interruptBackfillWindow = 16

    /// Settles the turns an agent on `surfaceID` ended without a hook, once its
    /// own activity report on the terminal ended at `edge` (Claude Code runs no
    /// Stop hook for an Esc interrupt). Hook or input activity after `edge` wins.
    ///
    /// - Parameters:
    ///   - surfaceID: The terminal surface whose agent reported the end of its activity.
    ///   - agentKind: The agent that reported it.
    ///   - edge: When the agent's activity report ended.
    /// - Returns: How many sessions left working or needs-input.
    @discardableResult
    func noteTurnSettled(surfaceID: String, agentKind: ChatAgentKind, at edge: Date) -> Int {
        guard !didShutdown else { return 0 }
        let settled = registry.noteTurnSettled(surfaceID: surfaceID, agentKind: agentKind, at: edge)
        for sessionID in settled {
            endProseTurn(sessionID: sessionID)
        }
        return settled.count
    }

    /// Applies what a live transcript batch says about the turn: Claude Code's
    /// user-interrupt marker ending the batch, then an assistant turn that
    /// completed without a Stop hook (Claude weekly-limit replies). Later hooks
    /// remain authoritative.
    ///
    /// - Parameters:
    ///   - sessionID: The session the batch belongs to.
    ///   - appended: The batch's newly appended messages, ascending seq.
    func noteTranscriptTurnEnd(sessionID: String, appended: [ChatMessage]) {
        noteTranscriptInterrupt(sessionID: sessionID, in: appended)
        if let completedAt = Self.completedAssistantTurnTimestamp(in: appended) {
            registry.noteAssistantTurnCompleted(sessionID: sessionID, at: completedAt)
        }
    }

    /// Settles a Claude turn when `messages` end with the marker Claude Code
    /// writes for a user interrupt: a live batch, or the newest messages of a
    /// transcript stopped while nothing tailed it. The registry ignores a
    /// marker older than the session's current turn.
    ///
    /// - Parameters:
    ///   - sessionID: The session the messages belong to.
    ///   - messages: Transcript messages, ascending seq.
    func noteTranscriptInterrupt(sessionID: String, in messages: [ChatMessage]) {
        guard !didShutdown,
              let interruptedAt = ChatMessage.trailingUserInterrupt(in: messages),
              registry.noteTranscriptInterrupt(sessionID: sessionID, at: interruptedAt) else { return }
        endProseTurn(sessionID: sessionID)
    }

    private static func completedAssistantTurnTimestamp(in messages: [ChatMessage]) -> Date? {
        guard !messages.isEmpty else { return nil }
        var completedAt: Date?
        for message in messages where message.role == .agent {
            switch message.kind {
            case .prose, .thought, .unsupported:
                completedAt = max(completedAt ?? message.timestamp, message.timestamp)
            case .toolUse, .terminal, .fileEdit, .permissionRequest, .question:
                return nil
            case .status:
                break
            case .attachment:
                break
            }
        }
        return completedAt
    }
}
