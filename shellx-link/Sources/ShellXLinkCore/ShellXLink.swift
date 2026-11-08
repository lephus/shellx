public enum ShellXLink {
    public static let protocolVersion = 1

    /// Largest attachment, in bytes (10 MiB); PROTOCOL.md section 5, "Attachments".
    public static let maxAttachmentBytes = 10_485_760
    /// Most attachments one `chat.send` may name.
    public static let maxAttachmentsPerMessage = 5
    /// Most finished uploads a Link session holds that no `chat.send` has used yet. A new upload past that drops the
    /// one that finished first (PROTOCOL.md section 5, "Attachments").
    public static let maxPendingUploads = 5
    /// How long a host keeps a session's unsent uploads after the last `attach.*` call it accepted; then every one is
    /// dropped and its id is `bad_request` (PROTOCOL.md section 5, "Attachments"). A phone that waited longer uploads
    /// again.
    public static let unsentUploadLifetime: Duration = .seconds(300)
    /// Most bytes of file data in one `attach.chunk` (the base64 form fits a frame).
    public static let maxAttachmentChunkBytes = 45_000
    /// The `welcome.features` entry of a host that takes attachments.
    public static let attachmentsFeature = "attachments"
    /// The `welcome.features` entry of a host that lists its workspaces (PROTOCOL.md section 4, "Workspace").
    public static let workspacesFeature = "workspaces"
    /// The `welcome.features` entry of a host that takes `workspace.create`, `workspace.rename` and `workspace.close`.
    public static let workspaceControlFeature = "workspace_control"
    /// The `welcome.features` entry of a host that takes `agent.close`.
    public static let agentCloseFeature = "agent_close"
    /// The `welcome.features` entry of a host that takes `terminal.close`.
    public static let terminalCloseFeature = "terminal_close"
    /// The `welcome.features` entry of a host that takes `terminal.view.*` (PROTOCOL.md section 11).
    public static let terminalViewFeature = "terminal_view"
    /// The `welcome.features` entry of a host that takes `terminal.create` (PROTOCOL.md section 11).
    public static let terminalCreateFeature = "terminal_create"
    /// Longest `title` of a `workspace.rename`, in UTF-8 bytes (about 128 Vietnamese characters). The host checks it;
    /// the codec does not.
    public static let maxWorkspaceTitleBytes = 512
}
