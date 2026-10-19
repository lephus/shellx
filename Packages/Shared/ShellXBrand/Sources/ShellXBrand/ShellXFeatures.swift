/// Compile-time feature switches. Wave 2 flips `remoteMachines`.
public enum ShellXFeatures {
    public static let remoteMachines = false

    /// CodeRouter is a Manaflow service that no ShellX wave replaces, so it
    /// stays off for good and does not follow `remoteMachines`: `cmux cr` and
    /// the CodeRouter passthrough never download, install or run a CodeRouter
    /// CLI (bundled, on PATH or in `~/.coderouter`).
    public static let codeRouter = false

    /// Manaflow Cloud: sign-in and accounts (Stack Auth, cmux.com), Cloud
    /// machines, VPN, remotes, AI-account upload, billing and Pro. No ShellX
    /// wave replaces it, so it stays off for good and does not follow
    /// `remoteMachines`; Wave 2's own relay never brings it back.
    /// ``ShellXCloudGate`` refuses its CLI verbs and socket methods.
    public static let cloud = false
}
