/// The CLI verbs and socket methods that reach a Manaflow service, and the
/// switch that keeps each one off. The CLI refuses a verb before it connects to
/// the app; the app's socket dispatcher refuses a method before any handler
/// runs. Neither depends on `ShellXFeatures.remoteMachines`.
public enum ShellXCloudGate {
    public enum Service: Sendable, Equatable {
        /// Sign-in, accounts, Cloud machines and billing (`ShellXFeatures.cloud`).
        case cloud
        /// CodeRouter (`ShellXFeatures.codeRouter`).
        case codeRouter
    }

    /// Socket method prefixes served by Manaflow Cloud.
    public static let cloudSocketMethodPrefixes = ["auth.", "vm.", "remotes.", "aiAccounts.", "billing."]
    /// Socket method prefixes served by CodeRouter.
    public static let codeRouterSocketMethodPrefixes = ["coderouter."]
    /// Local methods under a Cloud prefix: `auth.login` is the socket password
    /// handshake, which never leaves this Mac.
    public static let localSocketMethods = ["auth.login"]

    /// Top-level CLI verbs that only talk to Manaflow Cloud.
    public static let cloudCLICommands = [
        "auth", "login", "logout", "billing", "vm", "cloud", "vpn",
        "remotes", "remote", "ai-accounts",
        "vm-pty-attach", "vm-pty-connect", "vm-tui-connect", "vm-ssh-attach",
    ]
    /// Top-level CLI verbs that run or configure CodeRouter.
    public static let codeRouterCLICommands = ["coderouter", "cr"]

    /// The service that refuses `method`, or nil when the method is local.
    public static func unavailableService(forSocketMethod method: String) -> Service? {
        if localSocketMethods.contains(method) { return nil }
        if !ShellXFeatures.codeRouter, codeRouterSocketMethodPrefixes.contains(where: method.hasPrefix) {
            return .codeRouter
        }
        if !ShellXFeatures.cloud, cloudSocketMethodPrefixes.contains(where: method.hasPrefix) {
            return .cloud
        }
        return nil
    }

    /// The service that refuses the top-level CLI verb `command`, or nil.
    public static func unavailableService(forCLICommand command: String) -> Service? {
        let verb = command.lowercased()
        if !ShellXFeatures.codeRouter, codeRouterCLICommands.contains(verb) { return .codeRouter }
        if !ShellXFeatures.cloud, cloudCLICommands.contains(verb) { return .cloud }
        return nil
    }
}
