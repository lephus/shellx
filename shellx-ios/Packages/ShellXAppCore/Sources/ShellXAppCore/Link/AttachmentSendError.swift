import Foundation

/// Why a message with attachments surely did not reach its session (`MachineHub.chatSend` with
/// attachments). Nothing was typed, so the message can be sent again as it is.
public enum AttachmentSendError: Error, Equatable {
    /// The link failed while an attachment went up (a timeout, the session closed): the message
    /// itself was never sent.
    case uploadFailed
    /// The Mac refused an upload or the message that named them (`too_large`, `bad_request`,
    /// `unsupported`), or it does not take attachments (`unsupported`, never asked).
    case refused(code: String)
}
