import Foundation

/// What `HomeModel.submit` did with a message.
public enum HomeSubmitResult: Equatable, Sendable {
    /// Nothing was sent or noted; the validation says why: empty, too long, too many attachments or
    /// one too big.
    case refused(ComposerValidation)
    /// The message (its trimmed text) went into the conversation, with a note on what became of it.
    case added(String)
    /// A message with attachments that surely did not reach its session (nowhere to send it, its Mac
    /// offline, an upload failed, the Mac refused it or did not type it): only a note on why went
    /// into the conversation, and the composer keeps the text and the attachments to send again.
    case kept

    /// True when the composer keeps what it holds: a message refused on the phone that the user can
    /// fix, or one with attachments the Mac surely did not take.
    public var keepsDraft: Bool {
        switch self {
        case .refused(.empty), .refused(.ok), .added: return false
        case .refused, .kept: return true
        }
    }
}
