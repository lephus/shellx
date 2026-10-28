public enum ShellXLink {
    public static let protocolVersion = 1

    /// Largest attachment, in bytes (10 MiB); PROTOCOL.md section 5, "Attachments".
    public static let maxAttachmentBytes = 10_485_760
    /// Most attachments one `chat.send` may name.
    public static let maxAttachmentsPerMessage = 5
    /// Most uploads a Link session holds that no `chat.send` has used yet.
    public static let maxPendingUploads = 5
    /// Most bytes of file data in one `attach.chunk` (the base64 form fits a frame).
    public static let maxAttachmentChunkBytes = 45_000
    /// The `welcome.features` entry of a host that takes attachments.
    public static let attachmentsFeature = "attachments"
}
