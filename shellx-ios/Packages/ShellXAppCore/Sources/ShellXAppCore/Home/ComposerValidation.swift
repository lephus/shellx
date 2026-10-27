import Foundation

/// Whether the composer's text may be sent: trimmed at both ends, not empty, and at most
/// `maxBytes` UTF-8 bytes, the `chat.send` limit (PROTOCOL.md). Checked on the phone, so an
/// overlong paste or dictation is refused here and the Mac never has to answer a protocol error.
public enum ComposerValidation: Equatable, Sendable {
    /// Nothing but whitespace: nothing to do.
    case empty
    /// The trimmed text, ready to send.
    case ok(String)
    /// Too long to send; `bytes` is the trimmed text's UTF-8 length.
    case tooLong(bytes: Int)

    /// The most UTF-8 bytes one `chat.send` carries.
    public static let maxBytes = 16_384

    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = trimmed.utf8.count
        if bytes == 0 {
            self = .empty
        } else if bytes > Self.maxBytes {
            self = .tooLong(bytes: bytes)
        } else {
            self = .ok(trimmed)
        }
    }
}
