import Foundation
import os

/// The app's bridge server (Task 11), owned by `ShellXRemoteService`: started before the host daemon,
/// stopped on sign-out, on termination and before every re-start. Both calls are cheap and thread-safe.
public protocol RemoteBridgeControlling: Sendable {
    func start(socket: URL) throws
    func stop()
}

/// Opens a local workspace whose terminal runs the attach wrapper of a remote terminal (D8).
@MainActor
public protocol RemoteWorkspaceOpening: AnyObject, Sendable {
    /// The new workspace's id, or nil when no window can take it.
    func openRemoteTerminal(title: String, attachCommand: String) -> UUID?
}

/// What this Mac tells shellx-core and the other machines about itself.
public struct ShellXRemoteDevice: Equatable, Sendable {
    /// Machine and device name (`machines.register` / `config.set device_name`).
    public var machineName: String
    public var appVersion: String
    public var osVersion: String

    public init(machineName: String, appVersion: String, osVersion: String) {
        self.machineName = machineName; self.appVersion = appVersion; self.osVersion = osVersion
    }

    /// `base`, plus `" (DEV <tag>)"` for a tagged debug build (`<bundle>.debug.<tag>`), so a Release and a
    /// dev build on one Mac register as two recognisable machines (Review Focus 1).
    public static func machineName(base: String, bundleID: String) -> String {
        guard let marker = bundleID.range(of: ".debug.") else { return base }
        let tag = bundleID[marker.upperBound...]
        return tag.isEmpty ? "\(base) (DEV)" : "\(base) (DEV \(tag))"
    }
}

/// DEBUG-only sign-in for e2e runs against the fake API; the app fills it only under `#if DEBUG`.
/// Its descriptions never print the values.
public struct ShellXRemoteDevCredentials: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let email: String
    public let password: String

    public init(email: String, password: String) { self.email = email; self.password = password }

    public var description: String { "ShellXRemoteDevCredentials(<redacted>)" }
    public var debugDescription: String { description }
}

/// Everything `ShellXRemoteService` needs from the outside world, injected so the service runs in
/// package tests with fakes (Ruling R28).
public struct ShellXRemoteEnvironment: Sendable {
    public var core: ShellXCoreClient
    public var launcher: any SidecarLaunching
    public var clock: any RemoteClock
    public var paths: RemotePaths
    /// The bundled `Contents/Resources/bin/cmux-tui`.
    public var cmuxTui: URL
    /// `config.set api_base`.
    public var apiBase: URL
    public var device: ShellXRemoteDevice
    /// `ShellXFeatures.remoteMachines || (DEBUG && SHELLX_REMOTE_MACHINES == "1")`, read at start.
    public var gateEnabled: @Sendable () -> Bool
    public var devCredentials: ShellXRemoteDevCredentials?
    public var bridge: any RemoteBridgeControlling
    public var workspaceOpener: any RemoteWorkspaceOpening
    public var store: RemoteLinkStore

    public init(core: ShellXCoreClient, launcher: any SidecarLaunching, clock: any RemoteClock, paths: RemotePaths,
                cmuxTui: URL, apiBase: URL, device: ShellXRemoteDevice, gateEnabled: @escaping @Sendable () -> Bool,
                devCredentials: ShellXRemoteDevCredentials? = nil, bridge: any RemoteBridgeControlling,
                workspaceOpener: any RemoteWorkspaceOpening, store: RemoteLinkStore? = nil) {
        self.core = core; self.launcher = launcher; self.clock = clock; self.paths = paths
        self.cmuxTui = cmuxTui; self.apiBase = apiBase; self.device = device; self.gateEnabled = gateEnabled
        self.devCredentials = devCredentials; self.bridge = bridge; self.workspaceOpener = workspaceOpener
        self.store = store ?? RemoteLinkStore(paths: paths)
    }
}

/// Logging for the remote service: ids, codes and counts only, never a ticket, invite, password or token.
enum RemoteLog {
    static let service = Logger(subsystem: "pro.shellx.desktop", category: "remote-service")

    /// A short, secret-free code for an error (core codes verbatim, file errors by kind and errno).
    static func code(_ error: any Error) -> String {
        switch error {
        case let core as ShellXCoreError: return core.code
        case let file as OwnerOnlyFileError:
            switch file {
            case .insecureDirectory: return "state_dir_insecure"
            case .insecureFile: return "state_file_insecure"
            case .io(let operation, _, let errno): return "io_\(operation.replacingOccurrences(of: " ", with: "_"))_\(errno)"
            case .tooLarge: return "too_large"
            case .invalidName: return "invalid_name"
            }
        case is DecodingError: return "decode_failed"
        case is CancellationError: return "cancelled"
        default: return "error"
        }
    }
}
