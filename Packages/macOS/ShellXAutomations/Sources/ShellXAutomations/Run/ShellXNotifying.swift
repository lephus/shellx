/// Posts automation banners.
public protocol ShellXNotifying: Sendable {
    /// Shows `n` to the user.
    func post(_ n: ShellXAutomationNotification) async throws
}
