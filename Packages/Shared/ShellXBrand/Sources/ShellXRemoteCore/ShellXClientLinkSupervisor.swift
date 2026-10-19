import Foundation
import os
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Viewer side: one `cmux-tui remote connect` per remote machine, with a fresh `connect` ticket
/// (target = that machine) before every spawn and the 1, 2, 4, 8, 16, 30 s backoff between spawns.
/// A stdout line `{"event":"connection-snapshot",…}` means the link is up. While the machine is
/// offline nothing is spawned and no ticket is minted.
///
/// Upstream `remote connect` exits for good on a relay rejection (e.g. an expired ticket) or a lost
/// logical session, so every exit is restarted on the backoff. Once enrolled, restarts run without
/// `--invite-file` and with `--daemon <record.daemonFingerprint>` (the daemon pinned in the client
/// state dir). The positional route is always `RelayRoute.cmuxRoute(relay_url)` of the latest mint.
///
/// Invite file (single use, from `pair.poll {write_invite_to}`): passed as `--invite-file` until the
/// first `.connected`, then deleted and `record.enrolled = true` is saved. It is also deleted on every
/// path where the enrollment can no longer use it: `stop()` before connecting, a fatal failure
/// (`.failed`), and `inviteLifetime` after `start` without a connection (`invite_expired`).
public actor ShellXClientLinkSupervisor: LinkSupervising {
    /// Invites live at most 300 s (`remote enroll create --ttl`), counted here from `start`.
    public static let inviteLifetime: TimeInterval = 300
    static let snapshotEvent = "connection-snapshot"

    public nonisolated let machine: RemoteMachine.ID
    let deviceName: String
    let paths: RemotePaths
    let cmuxTui: URL
    let refresher: ShellXTicketRefresher
    let launcher: any SidecarLaunching
    let clock: any RemoteClock
    let store: RemoteLinkStore
    let stateContinuation: AsyncStream<LinkState>.Continuation
    public nonisolated let stateStream: AsyncStream<LinkState>
    var engine = LinkEngine()

    public private(set) var record: RemoteLinkRecord
    private var inviteFile: URL?
    private var inviteDeadline: Date?
    private var needsKeepFresh = true
    /// From the latest mint's `relay_url`; `record.route` is only a fallback before any mint.
    private var relayRoute: String?

    public var state: LinkState { engine.machine.state }

    public init(machine: RemoteMachine.ID, record: RemoteLinkRecord, deviceName: String, paths: RemotePaths,
                cmuxTui: URL, refresher: ShellXTicketRefresher, launcher: any SidecarLaunching, clock: any RemoteClock,
                store: RemoteLinkStore) {
        self.machine = machine
        self.record = record
        self.deviceName = deviceName
        self.paths = paths
        self.cmuxTui = cmuxTui
        self.refresher = refresher
        self.launcher = launcher
        self.clock = clock
        self.store = store
        (stateStream, stateContinuation) = AsyncStream.makeStream(of: LinkState.self)
    }

    var ticketName: String { paths.connectTicketName(for: machine) }
    var ticketFile: URL { paths.coreStateDir.appendingPathComponent("tickets/" + ticketName) }

    /// Starts the link. An invite given while the link already runs is never ignored: while connected
    /// it is not needed and is unlinked; otherwise it replaces any older invite (which is unlinked) and is
    /// used from the next spawn, with a fresh `inviteLifetime`.
    public func start(inviteFile: URL?) async {
        if let inviteFile, inviteFile != self.inviteFile {
            if case .connected = engine.machine.state {
                _ = unlink(inviteFile.path)
            } else {
                dropInvite()
                self.inviteFile = inviteFile
                inviteDeadline = clock.now.addingTimeInterval(Self.inviteLifetime)
            }
        }
        switch engine.machine.state {
        case .idle, .failed: break
        default: return
        }
        needsKeepFresh = true
        await feed(.start)
    }

    /// From the machine list / heartbeat: offline kills the link and stops minting; online starts it again.
    public func machineAvailability(online: Bool, lastSeen: Date?) async {
        await feed(online ? .machineOnline : .machineOffline(lastSeen: lastSeen))
    }

    public func stop() async {
        await feed(.stop)
        killProcess()
        dropInvite()
        await refresher.stop(name: ticketName)
        needsKeepFresh = true
    }

    // MARK: - LinkSupervising

    func prepareAndMint() async -> String? {
        if let deadline = inviteDeadline, inviteFile != nil, clock.now >= deadline { return "invite_expired" }
        do {
            try OwnerOnlyFile.ensurePrivateDirectory(paths.socketDir)
            try OwnerOnlyFile.ensurePrivateDirectory(paths.clientStateDir)
        } catch {
            return "state_dir_insecure"
        }
        do {
            if needsKeepFresh {
                needsKeepFresh = false
                try await refresher.keepFresh(name: ticketName, permission: "connect", target: machine)
            } else {
                try await refresher.mintNow(name: ticketName)
            }
        } catch {
            return LinkFailure.code(for: error)
        }
        // The positional route is always the full relay route from tickets.mint: cmux strips the path
        // from invite routes, so the invite's (or a stale record's) route must never be used.
        if let url = await refresher.relayURL(name: ticketName) {
            guard let route = try? RelayRoute.cmuxRoute(from: url) else { return "bad_relay_url" }
            relayRoute = route
        }
        return nil
    }

    func spawnCommand() -> (args: [String], env: [String: String]) {
        // Enrolled and no invite: pin the daemon known in the client state dir (as the e2e harness does).
        let pinned = inviteFile == nil && record.enrolled && !record.daemonFingerprint.isEmpty ? record.daemonFingerprint : nil
        return (RemoteCommandLine.connect(paths: paths, machine: machine, route: relayRoute ?? record.route, slot: record.slot,
                                          ticketFile: ticketFile, inviteFile: inviteFile, deviceName: deviceName,
                                          daemonFingerprint: pinned), [:])
    }

    func event(forLine line: String) -> LinkEvent? {
        guard Self.isSnapshotLine(line) else { return nil }
        let socket = paths.clientSocket(for: machine).path
        if case .connected(socket) = engine.machine.state { return nil }   // later snapshots: still up
        return .connected(localSocket: socket)
    }

    func didSpawn(generation: Int) {}

    func didPublish(_ state: LinkState) async {
        switch state {
        case .connected:
            if inviteFile != nil {
                dropInvite()
                record.enrolled = true
                // The enrollment itself lives in cmux-tui's client state; this flag only skips invites later.
                // Saved on the service's serial links.json queue, in order with its loads and removals.
                let store = self.store, saved = record
                do { try await ShellXRemoteService.onLinkStore { try store.upsert(saved) } } catch {
                    RemoteLog.service.error("link record not saved machine=\(self.machine, privacy: .public) error=\(RemoteLog.code(error), privacy: .public)")
                }
            }
        case .failed:
            dropInvite()
            await refresher.stop(name: ticketName)
            needsKeepFresh = true
        case .idle, .offline:
            await refresher.stop(name: ticketName)
            needsKeepFresh = true
        case .connecting, .reconnecting:
            break
        }
    }

    func mintAbandoned() async {
        switch engine.machine.state {
        case .idle, .failed, .offline:
            await refresher.stop(name: ticketName)
            needsKeepFresh = true
        default: break
        }
    }

    // MARK: - Helpers

    /// `remote connect --headless --json` prints `{"event":"connection-snapshot","local_socket":…,"connection":…}`
    /// once connected and on every topology change.
    static func isSnapshotLine(_ line: String) -> Bool {
        guard line.first == "{",
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return false }
        return object["event"] as? String == snapshotEvent
    }

    /// Removes the invite file itself (a symlink is unlinked, never followed).
    private func dropInvite() {
        if let inviteFile { _ = unlink(inviteFile.path) }
        inviteFile = nil
        inviteDeadline = nil
    }
}
