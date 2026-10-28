import Foundation

/// The message a screen's composer holds: its text and attachments, and the message with
/// attachments on its way, if any.
///
/// A message with attachments stays in the composer while it is sent; the composer is locked
/// meanwhile. When the answer comes, its text and the attachments that went are cleared, unless the
/// result keeps the draft to send again. An attachment added meanwhile (a photo that finished
/// loading after Send was tapped) was never sent, so it stays for the next message.
public struct ComposerDraft: Equatable, Sendable {
    public var text: String
    public var attachments: [OutgoingAttachment]
    /// The ids of the attachments of the message on its way; nil when none is.
    private var inFlight: Set<UUID>?

    public init(text: String = "", attachments: [OutgoingAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }

    /// True from `sendStarted()` to `sendEnded(keepsDraft:)`.
    public var isSending: Bool { inFlight != nil }

    /// The composer handed over its message with the attachments it holds now.
    public mutating func sendStarted() {
        inFlight = Set(attachments.map(\.id))
    }

    /// The answer came: unless `keepsDraft`, the text and the attachments that went are cleared.
    public mutating func sendEnded(keepsDraft: Bool) {
        guard let sent = inFlight else { return }
        inFlight = nil
        guard !keepsDraft else { return }
        text = ""
        attachments.removeAll { sent.contains($0.id) }
    }
}
