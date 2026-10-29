import Foundation
import ShellXLinkCore

/// What became of a message sent from an agent's screen.
public enum AgentSendResult: Equatable, Sendable {
    /// Not sent: the text is empty, or longer than one `chat.send` carries, or the attachments are
    /// too many or one is too big.
    case refused(ComposerValidation)
    /// The Mac's answer.
    case sent(ChatSendOutcome)
    /// The session's Mac is not online: nothing was sent or queued (spec section 7.5).
    case offline
    /// A message with attachments that surely did not reach the session: an upload failed (the link
    /// dropped, or the Mac refused it), or the Mac refused the message that named them. Nothing was
    /// typed; it can be sent again.
    case notSent
    /// A message with attachments that the Mac no longer takes them for (`unsupported`): nothing was
    /// typed, and sending it again will not help until the Mac takes attachments again.
    case attachmentsUnsupported
    /// The link failed before the Mac answered: the text may or may not have arrived.
    case noAnswer

    /// True when the Mac surely did not take the message, so the composer gets its text and
    /// attachments back to send again. Never after `submitted` or no answer, where sending again
    /// could deliver it twice.
    public var keepsDraft: Bool {
        switch self {
        case .refused(.tooLong), .refused(.tooManyAttachments), .refused(.attachmentTooLarge), .offline, .notSent,
             .attachmentsUnsupported:
            return true
        case .refused: return false
        case .sent(.submitted), .noAnswer: return false
        case .sent: return true
        }
    }
}
