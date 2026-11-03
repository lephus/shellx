/// The app-bundle paths `shellx routine` derives from its own location, `<App>.app/Contents/Resources/bin/shellx`.
public struct ShellXRoutineBundleLayout: Equatable, Sendable {
    /// The `shellx` executable launchd jobs call.
    public let cliPath: String
    /// The enclosing `.app` bundle.
    public let appPath: String

    /// The app's `Info.plist`.
    public var infoPlistPath: String { appPath + "/Contents/Info.plist" }
    /// The bundled notifier helper.
    public var notifierAppPath: String { appPath + "/Contents/Library/ShellX Notifier.app" }

    /// The layout for the CLI at `cliPath` (already resolved), or `nil` when it does not sit in an app bundle's `Contents/Resources/bin`.
    public init?(cliPath: String) {
        var components = cliPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 5 else { return nil }
        components.removeLast()
        guard components.removeLast() == "bin", components.removeLast() == "Resources", components.removeLast() == "Contents",
              let app = components.last, app.hasSuffix(".app"), app.count > 4 else { return nil }
        self.cliPath = cliPath
        appPath = "/" + components.joined(separator: "/")
    }
}
