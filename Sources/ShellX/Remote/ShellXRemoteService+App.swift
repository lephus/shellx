import Foundation
import SystemConfiguration
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
        // The host name is only looked up when remote machines can run. Otherwise (serving phones only, or
        // Settings → Account signing in with everything off) the device gets the Mac's computer name, a local
        // read, unlike `Host.current()`.
        let hostName = ShellXRemoteGate.isEnabled
            ? (Host.current().localizedName ?? processInfo.hostName)
            : (SCDynamicStoreCopyComputerName(nil, nil) as String? ?? ShellXBrand.appName)
        let system = processInfo.operatingSystemVersion
        let device = ShellXRemoteDevice(
            machineName: ShellXRemoteDevice.machineName(base: hostName, bundleID: bundleID),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            osVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)")
        let core = ShellXCoreClient(ShellXCoreFFI.shared)
        // ShellX Link: the agent Feed, sessions, chat and workspaces for phones. The service starts it only while
        // it serves phones (`ShellXRemoteGate.servesPhones`) and has a `link_slot` from `machines.register`.
        let workspaces = ShellXLinkWorkspaceSource()
        let feed = ShellXLinkFeedSource(coordinator: .shared)
        let linkHost = ShellXLinkHostController(
            core: core,
            storage: FallbackLinkSecretStorage.standard(onFallback: {
                ShellXLinkHostController.log.notice("link keys: the Keychain refuses this build; using the development file store")
            }),
            feed: feed,
            sessions: ShellXLinkSessionSource(),
            chat: ShellXLinkChatSource(),
            workspaces: workspaces,
            workspaceControl: workspaces,
            hostVersion: device.appVersion,
            machineName: device.machineName,
            phonePush: .live(feed: feed, core: core))
        return ShellXRemoteEnvironment(
            core: core,
            launcher: ShellXSidecarProcess(),
            clock: SystemRemoteClock(),
            paths: RemotePaths(bundleID: bundleID, home: FileManager.default.homeDirectoryForCurrentUser,
                               temporaryDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            cmuxTui: bundle.bundleURL.appendingPathComponent("Contents/Resources/bin/cmux-tui"),
            apiBase: apiBase,
            device: device,
            gateEnabled: { ShellXRemoteGate.servesPhones },
            devCredentials: devCredentials,
            bridge: ShellXAppBridgeController(),
            workspaceOpener: ShellXTabWorkspaceOpener(),
            linkHost: linkHost,
            remoteMachinesEnabled: { ShellXRemoteGate.isEnabled })
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
