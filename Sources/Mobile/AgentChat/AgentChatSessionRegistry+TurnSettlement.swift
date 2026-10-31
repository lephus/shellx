import CmuxAgentChat
import Foundation

/// Turns an agent ended without a hook. Claude Code runs no Stop hook when the
/// user stops a turn with Esc (or rejects a tool prompt with Esc) and then
/// waits at its prompt, its process alive, so neither a hook nor pid liveness
/// ever moves the session out of working. Two facts settle such a turn the way
/// the phone's own interrupt does (``noteInterrupted(sessionID:at:)``): idle,
/// still hook-established, and the next hook stays authoritative.
extension AgentChatSessionRegistry {
    /// Settles the turns an agent on one terminal ended without a hook: its own
    /// activity report on the terminal ended at `edge` (Claude Code's OSC 7501
    /// working or blocked record, re-checked after the sidebar's grace). A
    /// session with any hook or input after `edge` keeps its state, so a new
    /// prompt, tool call or answer always wins over the report.
    ///
    /// - Parameters:
    ///   - surfaceID: The terminal surface whose agent reported the end of its activity.
    ///   - agentKind: The agent that reported it; other agents on the terminal keep their state.
    ///   - edge: When the agent's activity report ended.
    /// - Returns: The sessions that left working or needs-input.
    @discardableResult
    func noteTurnSettled(surfaceID: String, agentKind: ChatAgentKind, at edge: Date) -> [String] {
        let sessionIDs = indexedRecords(surfaceID: surfaceID)
            .filter { record in
                guard record.agentKind == agentKind,
                      record.surfaceID == surfaceID,
                      record.lastActivityAt <= edge,
                      let since = Self.activeSince(record.state) else { return false }
                return since <= edge
            }
            .map(\.sessionID)
        for sessionID in sessionIDs {
            settleInterruptedTurn(sessionID: sessionID, at: edge)
        }
        return sessionIDs
    }

    /// Settles a Claude turn its transcript says the user interrupted: the
    /// marker Claude Code writes ends what the transcript holds. A marker from
    /// before the current working or needs-input state began belongs to an
    /// earlier turn, or a hook after it started a newer one, and settles
    /// nothing.
    ///
    /// - Parameters:
    ///   - sessionID: The session whose transcript holds the marker.
    ///   - marker: The interrupt marker's transcript time.
    /// - Returns: Whether the session left working or needs-input.
    @discardableResult
    func noteTranscriptInterrupt(sessionID: String, at marker: Date) -> Bool {
        guard let current = record(sessionID: sessionID),
              current.agentKind == .claude,
              let since = Self.activeSince(current.state),
              since <= marker else { return false }
        settleInterruptedTurn(sessionID: sessionID, at: marker)
        return true
    }

    /// When the current working or needs-input state began, or `nil` when the
    /// session is idle or ended.
    private nonisolated static func activeSince(_ state: ChatAgentState) -> Date? {
        switch state {
        case .working(let since), .needsInput(let since):
            return since
        case .idle, .ended:
            return nil
        }
    }

    /// The ``noteInterrupted(sessionID:at:)`` mutation: idle, keeping the
    /// hook-established state, with `time` as the latest activity.
    private func settleInterruptedTurn(sessionID: String, at time: Date) {
        update(sessionID: sessionID) { record in
            record.state = .idle
            record.lastActivityAt = max(record.lastActivityAt, time)
        }
    }
}
