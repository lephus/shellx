import Foundation

/// argv builders for cmux-tui; each flag is verified against `cmux-tui/crates/cmux-tui/src/main.rs` and `remote_cli.rs`.
public enum RemoteCommandLine {
    public static func serverStop(paths: RemotePaths) -> [String] {
        ["server", "stop", "--session", paths.session, "--socket", paths.muxSocket.path, "--force"]
    }

    public static func serverStart(paths: RemotePaths, route: String, slot: String, ticketFile: URL) -> [String] {
        ["server", "start", "--session", paths.session, "--socket", paths.muxSocket.path, "--headless", "--ephemeral",
         "--remote-state-dir", paths.daemonStateDir.path, "--remote-admin-socket", paths.adminSocket.path,
         "--remote-link-socket", paths.linkSocket.path, "--relay", route, "--relay-slot", slot,
         "--relay-ticket-file", ticketFile.path]
    }

    private static func enroll(_ action: String, _ positional: [String], paths: RemotePaths, extra: [String], json: Bool) -> [String] {
        ["remote", "enroll", action] + positional
            + ["--session", paths.session, "--state-dir", paths.daemonStateDir.path, "--admin-socket", paths.adminSocket.path]
            + extra + (json ? ["--json"] : [])
    }

    public static func enrollStatus(paths: RemotePaths) -> [String] { enroll("status", [], paths: paths, extra: [], json: true) }
    public static func enrollPending(paths: RemotePaths) -> [String] { enroll("pending", [], paths: paths, extra: [], json: true) }
    public static func enrollApprove(paths: RemotePaths, invitationID: String) -> [String] {
        enroll("approve", [invitationID], paths: paths, extra: [], json: false)
    }
    public static func enrollDeny(paths: RemotePaths, invitationID: String) -> [String] {
        enroll("deny", [invitationID], paths: paths, extra: [], json: false)
    }
    public static func enrollCreate(paths: RemotePaths, route: String, slot: String, ticketFile: URL, ttlSeconds: Int) -> [String] {
        enroll("create", [], paths: paths, extra: ["--advertise", route, "--relay-route", route, "--relay-slot", slot,
                                                   "--relay-ticket-file", ticketFile.path, "--ttl", String(ttlSeconds)], json: false)
    }

    /// `daemonFingerprint` pins the daemon already known in the client state dir (`--daemon`,
    /// `cmux-tui/src/remote_cli.rs` `parse_connect_flags`); used for enrolled restarts without an invite.
    public static func connect(paths: RemotePaths, machine: RemoteMachine.ID, route: String, slot: String,
                               ticketFile: URL, inviteFile: URL?, deviceName: String,
                               daemonFingerprint: String? = nil) -> [String] {
        ["remote", "connect", route, "--relay-slot", slot, "--relay-ticket-file", ticketFile.path,
         "--state-dir", paths.clientStateDir.path, "--local-socket", paths.clientSocket(for: machine).path,
         "--headless", "--json", "--exit-with-parent", "--device-name", deviceName]
            + (inviteFile.map { ["--invite-file", $0.path] } ?? [])
            + (daemonFingerprint.map { ["--daemon", $0] } ?? [])
    }

    /// Pane patience: give up after this many consecutive failed attaches (about 90 s at 2 s sleeps),
    /// which must outlast the link's own backoff (1+2+4+8+16+30 s).
    static let attachMaxConsecutiveFailures = 45
    static let attachRetryDelaySeconds = 2
    /// An attach that ran at least this long counts as a good connection and resets the failure counter.
    static let attachResetAfterSeconds = 10

    /// D8: `sh -c` reconnect loop around `<client> --socket <sock> attach --terminal <id>`.
    /// The values travel as quoted positional parameters, so nothing is ever re-parsed as shell code.
    public static func attachShellCommand(clientPath: String, socketPath: String, terminalID: String) -> String {
        attachShellCommand(clientPath: clientPath, socketPath: socketPath, terminalID: terminalID,
                           retryDelaySeconds: attachRetryDelaySeconds, maxFailures: attachMaxConsecutiveFailures,
                           resetAfterSeconds: attachResetAfterSeconds)
    }

    static func attachShellCommand(clientPath: String, socketPath: String, terminalID: String,
                                   retryDelaySeconds: Int, maxFailures: Int, resetAfterSeconds: Int) -> String {
        let script = """
        n=0; while :; do s=$(date +%s); "$1" --socket "$2" attach --terminal "$3"; [ $? -eq 0 ] && exit 0; \
        e=$(date +%s); [ $((e-s)) -ge \(resetAfterSeconds) ] && n=0; n=$((n+1)); \
        if [ "$n" -ge \(maxFailures) ]; then printf '\\r\\n[ShellX] phiên đã kết thúc / session ended\\r\\n'; exit 0; fi; \
        printf '\\r\\n[ShellX] đang kết nối lại… / reconnecting…\\r\\n'; sleep \(retryDelaySeconds); done
        """
        return (["sh", "-c", script, "sh", clientPath, socketPath, terminalID]).map(quote).joined(separator: " ")
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
