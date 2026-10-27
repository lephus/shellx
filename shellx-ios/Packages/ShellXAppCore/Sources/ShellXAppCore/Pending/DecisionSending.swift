import Foundation
import ShellXLinkCore

/// Sends a decision on a pending item to its Mac and returns what the Mac did with it.
/// `MachineHub` is the real one; tests script their own.
public protocol DecisionSending: Sendable {
    /// Throws `LinkCallError` when nothing was sent, `LinkClientError` when the call failed.
    @MainActor func reply(_ key: PendingKey, decision: LinkDecision) async throws -> ReplyOutcome
}
