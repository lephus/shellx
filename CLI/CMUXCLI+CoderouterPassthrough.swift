import Foundation
import ShellXBrand

// `cmux cr ...`, and every `cmux coderouter ...` verb cmux does not own
// (CMUXCLI+Coderouter.swift), would run the separately distributed CodeRouter
// CLI. CodeRouter is a Manaflow service that no ShellX wave replaces, so ShellX
// never downloads, installs or runs it: `runCoderouterAlias` (cmux.swift)
// stops at `ShellXFeatures.codeRouter`, which is always false and does not
// depend on `ShellXFeatures.remoteMachines`, and exits 127 with
// ``coderouterNotAvailable()`` before it looks for an executable. The locator
// below is kept for that upstream exec path and is never reached.
extension CMUXCLI {
    private static let coderouterExecutableNames = ["coderouter", "cr"]

    /// Where CodeRouter's installer puts the binary: `$CODEROUTER_INSTALL/bin`,
    /// default `$HOME/.coderouter/bin`.
    static func coderouterInstallBinDirectory(environment: [String: String]) -> URL {
        let explicitRoot = environment["CODEROUTER_INSTALL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let root: URL
        if !explicitRoot.isEmpty {
            root = URL(fileURLWithPath: explicitRoot, isDirectory: true)
        } else {
            let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
            root = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".coderouter", isDirectory: true)
        }
        return root.appendingPathComponent("bin", isDirectory: true)
    }

    func runCoderouterAlias(commandArgs: [String]) throws {
        try runCoderouterAlias(
            commandArgs: commandArgs,
            explicitSocketPath: nil,
            explicitPassword: nil,
            environment: ProcessInfo.processInfo.environment,
            bundleIdentifier: CLISocketPathResolver.currentAppBundleIdentifier() ?? ShellXBrand.bundleID
        )
    }

    /// The app-bundled core first, then PATH (`coderouter`, then `cr`), then the
    /// installer's bin directory. No hit involves the network. ShellX never
    /// calls this: `runCoderouterAlias` refuses first (`ShellXFeatures.codeRouter`).
    func resolveCoderouterExecutable(environment: [String: String]) -> String? {
        if let bundle = CLIExecutableLocator.enclosingAppBundle() {
            let binary = bundle.bundleURL.appendingPathComponent("Contents/Resources/bin/coderouter")
            if FileManager.default.isExecutableFile(atPath: binary.path) {
                return binary.path
            }
        }
        for name in Self.coderouterExecutableNames {
            if let path = resolveExecutableInPath(name, searchPath: environment["PATH"]) {
                return path
            }
        }
        return resolveExecutableInPath(
            "coderouter",
            searchPath: Self.coderouterInstallBinDirectory(environment: environment).path
        )
    }

    // MARK: - Presentation

    /// What every `cmux cr` and passthrough `cmux coderouter` invocation ends
    /// with in ShellX: a neutral message on stderr and exit 127, the "command
    /// not found" status scripts already handle. Nothing is downloaded,
    /// installed or run, and no install command is suggested.
    static func coderouterNotAvailable() -> CLIError {
        coderouterUnavailable(localizedPassthroughString(
            "cli.coderouter.unavailable",
            defaultValue: "CodeRouter is not available in ShellX."
        ))
    }

    /// Every way of not running CodeRouter exits 127; the reason is on stderr.
    private static func coderouterUnavailable(_ message: String) -> CLIError {
        CLIError(message: message, exitCode: 127)
    }

    /// An explicit `AppleLanguages` override wins, then the app bundle's
    /// catalog in the user's language, then the English default.
    private static func localizedPassthroughString(_ key: String, defaultValue: String) -> String {
        CMUXDiffViewerLocalization.string(key, defaultValue: defaultValue)
    }
}
