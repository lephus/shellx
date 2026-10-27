import Foundation

/// Why a decision was not taken.
public enum DecisionFailure: Equatable, Sendable {
    /// The Mac had no live, synced session: nothing was sent, and nothing will be sent by itself
    /// when it is back (spec section 7.5: no queue).
    case offline
    /// The Mac did not answer, even after one resend. Trying again is safe.
    case noAnswer
    /// The Mac answered that it cannot take this decision (`unknown`, or an error).
    case rejected
}
