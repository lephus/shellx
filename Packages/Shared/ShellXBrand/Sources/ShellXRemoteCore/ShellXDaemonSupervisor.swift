import Foundation

/// Host side: runs this Mac's `cmux-tui server start` sidecar, registered at the relay with a
/// `register` ticket, and restarts it on the 1, 2, 4, 8, 16, 30 s backoff with a fresh ticket each time.
///
/// Every spawn: socket and daemon state dirs ensured `0700` → `server stop --force` for this bundle's
/// session (a daemon left by a crash or force quit, Review Focus 5) → ticket mint → `server start`
/// with only `CMUX_SHELLX_BRIDGE_SOCKET` added to the scrubbed env → `remote enroll status --json`
/// polled every 250 ms for up to 10 s → `.connected(localSocket: muxSocket)`.
public actor ShellXDaemonSupervisor: LinkSupervising {
    public static let registerTicketName = "register.ticket"
    public static let bridgeSocketEnvironmentKey = "CMUX_SHELLX_BRIDGE_SOCKET"
    static let probeInterval: TimeInterval = 0.25
    static let probeTimeout: TimeInterval = 10
    /// Exit status reported when the daemon never answered `enroll status`.
    static let probeTimeoutStatus: Int32 = -2

    let paths: RemotePaths
    let cmuxTui: URL
    let core: ShellXCoreClient
    let refresher: ShellXTicketRefresher
    let launcher: any SidecarLaunching
    let clock: any RemoteClock
    let stateContinuation: AsyncStream<LinkState>.Continuation
    public nonisolated let stateStream: AsyncStream<LinkState>
    var engine = LinkEngine()

    private var route = ""
    private var slot = ""
    /// True until the refresher has been (re)registered for this run.
    private var needsKeepFresh = true

    public private(set) var daemonFingerprint: String?
    public var state: LinkState { engine.machine.state }

    /// `core` is kept for the app's other daemon-side calls; tickets go through `refresher`.
    public init(paths: RemotePaths, cmuxTui: URL, core: ShellXCoreClient, refresher: ShellXTicketRefresher,
                launcher: any SidecarLaunching, clock: any RemoteClock) {
        self.paths = paths
        self.cmuxTui = cmuxTui
        self.core = core
        self.refresher = refresher
        self.launcher = launcher
        self.clock = clock
        (stateStream, stateContinuation) = AsyncStream.makeStream(of: LinkState.self)
    }

    var ticketFile: URL { paths.coreStateDir.appendingPathComponent("tickets/" + Self.registerTicketName) }

    public func start(route: String, slot: String) async {
        switch engine.machine.state {
        case .idle, .failed: break
        default: return
        }
        self.route = route
        self.slot = slot
        needsKeepFresh = true
        await feed(.start)
    }

    /// Terminates the sidecar and stops this session's daemon (`server stop --force`).
    public func stop() async {
        await feed(.stop)
        killProcess()
        await refresher.stop(name: Self.registerTicketName)
        needsKeepFresh = true
        _ = try? await launcher.run(cmuxTui, RemoteCommandLine.serverStop(paths: paths), env: [:])
    }

    // MARK: - LinkSupervising

    func prepareAndMint() async -> String? {
        do {
            try OwnerOnlyFile.ensurePrivateDirectory(paths.socketDir)
            try OwnerOnlyFile.ensurePrivateDirectory(paths.daemonStateDir)
        } catch {
            return "state_dir_insecure"
        }
        // Review Focus 5: a daemon of this session may survive a crash; stop it first. Status ignored.
        _ = try? await launcher.run(cmuxTui, RemoteCommandLine.serverStop(paths: paths), env: [:])
        do {
            if needsKeepFresh {
                needsKeepFresh = false
                try await refresher.keepFresh(name: Self.registerTicketName, permission: "register", target: nil)
            } else {
                try await refresher.mintNow(name: Self.registerTicketName)
            }
            return nil
        } catch {
            return LinkFailure.code(for: error)
        }
    }

    func spawnCommand() -> (args: [String], env: [String: String]) {
        (RemoteCommandLine.serverStart(paths: paths, route: route, slot: slot, ticketFile: ticketFile),
         [Self.bridgeSocketEnvironmentKey: paths.bridgeSocket.path])
    }

    nonisolated func event(forLine line: String) -> LinkEvent? { nil }

    func didSpawn(generation: Int) {
        engine.probeTask = Task { [weak self] in await self?.probeUntilUp(generation: generation) }
    }

    func didPublish(_ state: LinkState) async {
        switch state {
        case .idle, .failed:
            await refresher.stop(name: Self.registerTicketName)
            needsKeepFresh = true
        default: break
        }
    }

    // MARK: - Probe

    private func probeUntilUp(generation: Int) async {
        let started = clock.now
        var polls = 0
        while isCurrentProcess(generation), !Task.isCancelled {
            let reply = try? await launcher.run(cmuxTui, RemoteCommandLine.enrollStatus(paths: paths), env: [:])
            guard isCurrentProcess(generation), !Task.isCancelled else { return }
            if let reply, reply.status == 0, let fingerprint = Self.daemonFingerprint(fromStatus: reply.stdout) {
                daemonFingerprint = fingerprint
                engine.probeTask = nil
                await feed(.connected(localSocket: paths.muxSocket.path))
                return
            }
            polls += 1
            let next = started.addingTimeInterval(Self.probeInterval * Double(polls))
            if next.timeIntervalSince(started) > Self.probeTimeout {
                await abandonProcess(generation: generation, status: Self.probeTimeoutStatus)
                return
            }
            do { try await clock.sleep(until: next) } catch { return }
        }
    }

    /// `remote enroll status --json` prints the admin `DaemonStatus`
    /// `{daemon_name, daemon_fingerprint, connected_clients}` and exits 0 once the daemon answers.
    static func daemonFingerprint(fromStatus stdout: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any],
              let fingerprint = object["daemon_fingerprint"] as? String, !fingerprint.isEmpty else { return nil }
        return fingerprint
    }
}
