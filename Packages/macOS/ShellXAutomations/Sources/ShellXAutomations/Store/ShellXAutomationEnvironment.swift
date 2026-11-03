public import Foundation

/// Where automations live on disk and how their launchd jobs are named, for one app bundle.
public struct ShellXAutomationEnvironment: Sendable {
    /// Bundle identifier of the release app.
    public static let releaseBundleIdentifier = "pro.shellx.desktop"

    /// Bundle identifier this environment was built for.
    public let bundleIdentifier: String
    /// Folder Claude Code loads skills from (`~/.claude/skills`), for every bundle.
    public let skillsRoot: URL
    /// Folder holding cronjob and workflow automations.
    public let automationsRoot: URL
    /// Folder launchd reads per-user agents from.
    public let launchAgentsDirectory: URL
    /// Prefix of every launchd label ShellX owns; the automation id follows it.
    public let labelPrefix: String
    /// Path of the `shellx` command line tool launchd jobs call.
    public let cliPath: String
    /// Path of the notifier helper app.
    public let notifierAppPath: String

    /// File whose replacement signals that automations or runs changed.
    public var changeStampURL: URL { automationsRoot.appending(path: ".changed") }

    /// Creates the environment for `bundleIdentifier`; any bundle other than the release one gets its own dev root and label prefix.
    public init(bundleIdentifier rawBundleIdentifier: String, home: URL, cliPath: String, notifierAppPath: String) {
        let bundleIdentifier = Self.sanitized(rawBundleIdentifier)
        self.bundleIdentifier = bundleIdentifier
        skillsRoot = home.appending(path: ".claude/skills", directoryHint: .isDirectory)
        launchAgentsDirectory = home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
        if bundleIdentifier == Self.releaseBundleIdentifier {
            automationsRoot = home.appending(path: ".shellx/automations", directoryHint: .isDirectory)
            labelPrefix = "pro.shellx.automation."
        } else {
            automationsRoot = home.appending(path: ".shellx/automations-dev/\(bundleIdentifier)", directoryHint: .isDirectory)
            labelPrefix = "pro.shellx.automation.dev.\(bundleIdentifier)."
        }
        self.cliPath = cliPath
        self.notifierAppPath = notifierAppPath
    }

    /// Keeps ASCII letters, digits, `.`, `-` and `_`; everything else, and any `..`, becomes `_`, so the id is one safe path component.
    private static func sanitized(_ identifier: String) -> String {
        let allowed = identifier.unicodeScalars.map { scalar -> Character in
            let v = scalar.value
            let ok = (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || scalar == "." || scalar == "-" || scalar == "_"
            return ok ? Character(scalar) : "_"
        }
        var result = String(allowed).replacingOccurrences(of: "..", with: "__")
        if result.hasPrefix(".") { result = "_" + result.dropFirst() }
        return result.isEmpty ? "_" : result
    }
}
