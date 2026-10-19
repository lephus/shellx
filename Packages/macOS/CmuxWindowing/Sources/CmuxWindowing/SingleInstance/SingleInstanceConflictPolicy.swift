public import Foundation

/// What a launching cmux does about another running process with its bundle id.
///
/// The newest launch used to force-terminate every older instance. When the
/// newcomer is a different bundle that shares the id (a locally built Release
/// app, a copy in Downloads, a tool launching a build under a profiler), that
/// killed the user's running app and its live agent sessions without a final
/// session save (incident 2026-09-26). Ordinary launches now yield to an
/// existing instance, including a relaunch of the same bundle. Deliberate
/// reload tooling must opt into replacement explicitly.
public struct SingleInstanceConflictPolicy: Sendable {
    public enum Action: Equatable, Sendable {
        /// This launch is explicitly authorized to replace the older instance.
        case replaceExisting
        /// A different bundle: leave the running app alone and exit.
        case yieldToExisting
        /// An older, non-native ShellX (the Flutter app) shares the bundle id:
        /// ask the user whether to quit it before launching. Never quit it
        /// without the user's answer.
        case askToQuitOlderShellX
    }

    /// What the running app that shares our bundle id is.
    public enum ExistingInstanceKind: Equatable, Sendable {
        /// A native (cmux-based) ShellX build.
        case nativeShellX
        /// Another app with the ShellX bundle id, such as the Flutter ShellX.
        case olderShellX
        /// LaunchServices did not report the bundle path.
        case unknown
    }

    /// What a running instance does when another app with its bundle id launches.
    public enum DuplicateLaunchAction: Equatable, Sendable {
        /// The same bundle relaunched; the newcomer yields on its own.
        case ignoreSameBundle
        /// An older (Flutter) ShellX, or a bundle that cannot be verified:
        /// leave it running, never kill it silently.
        case leaveOlderShellXRunning
        /// Another native copy: quit it, as before.
        case terminateDuplicate
    }

    /// The bundled CLI every native ShellX ships (the cmux-cli target's "Copy CLI" phase).
    public static let nativeBundleMarkerPath = "Contents/Resources/bin/shellx"

    /// The Flutter engine the previous ShellX app embeds.
    public static let flutterFrameworkPath = "Contents/Frameworks/FlutterMacOS.framework"

    /// Environment variable that restores the replace-anything behavior for a
    /// deliberate swap, e.g. `CMUX_ALLOW_REPLACING_RUNNING_CMUX=1`.
    public static let allowReplacingEnvironmentKey = "CMUX_ALLOW_REPLACING_RUNNING_CMUX"

    /// Seconds a replaced instance gets to quit (and save its session)
    /// before it is force-terminated.
    public static let gracefulTerminationTimeout: TimeInterval = 10

    /// The launching process's environment (only the override key is read).
    public let environment: [String: String]

    public init(environment: [String: String]) {
        self.environment = environment
    }

    public func action(
        currentBundleURL _: URL,
        existingBundleURL _: URL?
    ) -> Action {
        // Keep the deliberate reload escape hatch independent of bundle-path
        // discovery. The old behavior allowed this override to replace an
        // instance even when LaunchServices did not report its bundle URL.
        if environment[Self.allowReplacingEnvironmentKey] == "1" {
            return .replaceExisting
        }
        return .yieldToExisting
    }

    /// The action for an existing instance whose kind is known.
    ///
    /// An older ShellX is always asked about, even with
    /// ``allowReplacingEnvironmentKey``: the override is reload tooling for
    /// native builds and must not quit the user's other app.
    public func action(
        currentBundleURL: URL,
        existingBundleURL: URL?,
        existingKind: ExistingInstanceKind
    ) -> Action {
        if existingKind == .olderShellX {
            return .askToQuitOlderShellX
        }
        return action(currentBundleURL: currentBundleURL, existingBundleURL: existingBundleURL)
    }

    /// Classifies the running app at `bundleURL` from its bundle contents.
    ///
    /// Native ShellX always ships ``nativeBundleMarkerPath``; the Flutter
    /// ShellX embeds ``flutterFrameworkPath`` and has no bundled CLI. A bundle
    /// with the Flutter engine, or without the CLI, is an older ShellX.
    ///
    /// - Parameters:
    ///   - bundleURL: The running app's bundle, or nil when unknown.
    ///   - fileExists: File probe (`FileManager.fileExists(atPath:)` in the app).
    public static func classifyExistingBundle(
        at bundleURL: URL?,
        fileExists: (String) -> Bool
    ) -> ExistingInstanceKind {
        guard let bundleURL else { return .unknown }
        let root = bundleURL.standardizedFileURL
        if fileExists(root.appendingPathComponent(flutterFrameworkPath).path) {
            return .olderShellX
        }
        if fileExists(root.appendingPathComponent(nativeBundleMarkerPath).path) {
            return .nativeShellX
        }
        return .olderShellX
    }

    /// What a running native instance does when `launchedBundleURL` starts
    /// with the same bundle id.
    public static func duplicateLaunchAction(
        launchedBundleURL: URL?,
        currentBundleURL: URL,
        launchedKind: ExistingInstanceKind
    ) -> DuplicateLaunchAction {
        if let launchedBundleURL, isSameBundle(launchedBundleURL, currentBundleURL) {
            return .ignoreSameBundle
        }
        // An unverifiable bundle (no path from LaunchServices) could be the
        // Flutter ShellX, so it is left running too: only a verified native copy
        // is ever terminated.
        if launchedKind == .olderShellX || launchedKind == .unknown {
            return .leaveOlderShellXRunning
        }
        return .terminateDuplicate
    }

    /// Whether two bundle URLs resolve to the same installed application.
    public static func isSameBundle(_ lhs: URL, _ rhs: URL) -> Bool {
        canonical(lhs) == canonical(rhs)
    }

    private static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
