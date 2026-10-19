import Foundation
import ShellXBrand
import ShellXRemoteCore

/// ShellX: lets `AppDelegate` (and the sidebar) name the K4 service without importing the package.
typealias ShellXRemoteService = ShellXRemoteCore.ShellXRemoteService

/// ShellX: the core's C entry point is the service's `ShellXCoreCalling`; its `call(method:json:)` already
/// matches. The service only calls it off the main thread.
extension ShellXCoreFFI: ShellXCoreCalling {}

extension ShellXRemoteService {
    /// ShellX: the app's remote service (K4), built from the real core, cmux-tui, clock, paths, bridge and
    /// window. `AppDelegate` calls `startIfEnabled()` at launch and `stopForTermination()` on quit.
    @MainActor static let shared = ShellXRemoteService(environment: .forApp())
}

extension ShellXRemoteEnvironment {
    /// ShellX: everything for this bundle. `SHELLX_API_BASE`, `SHELLX_DEV_EMAIL` and `SHELLX_DEV_PASSWORD`
    /// are read only in DEBUG builds (e2e against the fake API).
    @MainActor
    static func forApp(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> ShellXRemoteEnvironment {
        let bundleID = bundle.bundleIdentifier ?? ShellXBrand.bundleID
        let environment = processInfo.environment
        let apiBase: URL = {
            #if DEBUG
            if let override = environment["SHELLX_API_BASE"], let url = URL(string: override) { return url }
            #endif
            return ShellXBrand.apiBaseURL
        }()
        let devCredentials: ShellXRemoteDevCredentials? = {
            #if DEBUG
            if let email = environment["SHELLX_DEV_EMAIL"], let password = environment["SHELLX_DEV_PASSWORD"],
               !email.isEmpty, !password.isEmpty {
                return ShellXRemoteDevCredentials(email: email, password: password)
            }
            #endif
            return nil
        }()
        // The host name is only looked up when the feature can run.
        let hostName = ShellXRemoteGate.isEnabled ? (Host.current().localizedName ?? processInfo.hostName) : ShellXBrand.appName
        let system = processInfo.operatingSystemVersion
        let device = ShellXRemoteDevice(
            machineName: ShellXRemoteDevice.machineName(base: hostName, bundleID: bundleID),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            osVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)")
        return ShellXRemoteEnvironment(
            core: ShellXCoreClient(ShellXCoreFFI.shared),
            launcher: ShellXSidecarProcess(),
            clock: SystemRemoteClock(),
            paths: RemotePaths(bundleID: bundleID, home: FileManager.default.homeDirectoryForCurrentUser,
                               temporaryDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            cmuxTui: bundle.bundleURL.appendingPathComponent("Contents/Resources/bin/cmux-tui"),
            apiBase: apiBase,
            device: device,
            gateEnabled: { ShellXRemoteGate.isEnabled },
            devCredentials: devCredentials,
            bridge: ShellXAppBridgeController(),
            workspaceOpener: ShellXTabWorkspaceOpener())
    }
}

/// ShellX: the bridge server (Task 11) behind the service's start/stop, serving the Mac's real terminals.
/// One server at a time; both calls are safe from any thread.
final class ShellXAppBridgeController: RemoteBridgeControlling, @unchecked Sendable {
    private let host: TerminalControllerBridgeHost
    private let lock = NSLock()
    private var server: ShellXBridgeServer?

    @MainActor
    init() {
        host = TerminalControllerBridgeHost()
    }

    func start(socket: URL) throws {
        stop()
        let candidate = ShellXBridgeServer(socket: socket, host: host)
        try candidate.start()
        lock.lock()
        server = candidate
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let current = server
        server = nil
        lock.unlock()
        current?.stop()
    }
}

/// ShellX: opens a remote terminal as a new workspace of the active window; its terminal runs the D8
/// attach wrapper (`RemoteCommandLine.attachShellCommand`).
@MainActor
final class ShellXTabWorkspaceOpener: RemoteWorkspaceOpening {
    func openRemoteTerminal(title: String, attachCommand: String) -> UUID? {
        guard let app = AppDelegate.shared,
              let manager = app.activeTabManagerForCommands(preferredWindow: nil) ?? app.tabManager,
              !manager.isFinalizedForWindowClose else { return nil }
        return manager.addWorkspaceIfActive(title: title, initialTerminalCommand: attachCommand)?.id
    }
}
