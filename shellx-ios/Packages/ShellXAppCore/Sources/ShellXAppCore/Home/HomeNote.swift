import Foundation
import ShellXLinkCore

/// A canned line from ShellX in the home conversation (plan decision D7). Not AI: each case has
/// one fixed sentence in the app's strings.
public enum HomeNote: Codable, Equatable, Sendable {
    /// "Sent to Claude Code in shellx."
    case sent(SessionRef)
    /// The Mac answered, but the session did not take the message.
    case sendFailed(SessionRef, SendFailure)
    /// "MacBook Pro is offline." Nothing was sent or queued (spec section 7.5).
    case machineOffline(machineName: String)
    /// "Not sent: MacBook Pro needs to be paired again." The Mac removed this iPhone, or its key
    /// changed: it will not come back by itself, so it is not called offline.
    case machineNeedsPairing(machineName: String)
    /// No Claude Code session is running on any online Mac.
    case noLiveSession
    /// "Claude Code in shellx is done: <first line of its last reply>"; nil when there is none.
    case agentFinished(SessionRef, summary: String?)
}

extension HomeNote {
    /// The note for the Mac's answer to `chat.send`. An outcome this app does not know counts as
    /// `failed`.
    init(sendOutcome: ChatSendOutcome, to ref: SessionRef) {
        switch sendOutcome {
        case .submitted: self = .sent(ref)
        case .notFound: self = .sendFailed(ref, .notFound)
        case .busy: self = .sendFailed(ref, .busy)
        case .failed, .other: self = .sendFailed(ref, .failed)
        }
    }

    /// The note for a `chat.send` that threw: an offline Mac (nothing was sent) names itself; any
    /// other error leaves it unknown whether the message arrived.
    init(sendError: any Error, to ref: SessionRef) {
        if case let LinkCallError.offline(machineName) = sendError {
            self = .machineOffline(machineName: machineName)
        } else {
            self = .sendFailed(ref, .noAnswer)
        }
    }
}
