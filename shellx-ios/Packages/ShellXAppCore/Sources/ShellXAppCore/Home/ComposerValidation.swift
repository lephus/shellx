import Foundation
import ShellXLinkCore

/// Whether the composer's message may be sent: its text trimmed at both ends and at most `maxBytes`
/// UTF-8 bytes, the `chat.send` limit (PROTOCOL.md), with at most
/// `ShellXLink.maxAttachmentsPerMessage` attachments of at most `ShellXLink.maxAttachmentBytes`
/// each. A message needs text or an attachment. Checked on the phone, so an overlong paste or
/// dictation, or too many or too big attachments, are refused here and the Mac never has to answer
/// a protocol error.
public enum ComposerValidation: Equatable, Sendable {
    /// Nothing but whitespace, and no attachment: nothing to do.
    case empty
    /// The trimmed text, ready to send; empty for a message of attachments only.
    case ok(String)
    /// Too long to send; `bytes` is the trimmed text's UTF-8 length.
    case tooLong(bytes: Int)
    /// More attachments than one message carries.
    case tooManyAttachments
    /// The attachment called `name` is bigger than one upload may be.
    case attachmentTooLarge(name: String)

    /// The most UTF-8 bytes one `chat.send` carries.
    public static let maxBytes = 16_384

    public init(_ text: String) {
        self.init(text, attachmentCount: 0)
    }

    /// The text, with `attachmentCount` attachments: empty text is `.ok("")` when there is at least
    /// one. Their sizes are `check(_:)`'s.
    public init(_ text: String, attachmentCount: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = trimmed.utf8.count
        if bytes > Self.maxBytes {
            self = .tooLong(bytes: bytes)
        } else if attachmentCount > ShellXLink.maxAttachmentsPerMessage {
            self = .tooManyAttachments
        } else if bytes == 0, attachmentCount == 0 {
            self = .empty
        } else {
            self = .ok(trimmed)
        }
    }

    /// Why `attachments` cannot go with one message (too many, or the first one too big); nil when
    /// they can.
    public static func check(_ attachments: [OutgoingAttachment]) -> ComposerValidation? {
        if attachments.count > ShellXLink.maxAttachmentsPerMessage { return .tooManyAttachments }
        if let big = attachments.first(where: { $0.data.count > ShellXLink.maxAttachmentBytes }) {
            return .attachmentTooLarge(name: big.name)
        }
        return nil
    }

    /// The text and the attachments together: the first reason not to send them, or `.ok`. What
    /// the composer and the models check before any call.
    public static func message(_ text: String, attachments: [OutgoingAttachment]) -> ComposerValidation {
        let validation = ComposerValidation(text, attachmentCount: attachments.count)
        guard case .ok = validation else { return validation }
        return check(attachments) ?? validation
    }
}
