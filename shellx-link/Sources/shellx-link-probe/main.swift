// shellx-link-probe: plays a paired phone for ShellX Link.
//
// It signs in to the ShellX relay as a `mobile` device, pairs with a Mac from the QR offer, mints its
// own connect tickets, and then watches and answers the Mac's agent requests, lists agent sessions,
// chats with them, and measures latency. Everything it keeps lives in `--state <dir>` (owner-only).
// It never prints the password, the token, a ticket, the private key or the offer's pairing code.

import Darwin
import Foundation

enum Probe {
    static let usage = """
        usage:
          shellx-link-probe login --state <dir> --api <url> --email <email> --password-stdin [--device-name <name>]
          shellx-link-probe pair --state <dir> --offer-file <file>
          shellx-link-probe machines --state <dir>
          shellx-link-probe unpair --state <dir> --machine <id>
          shellx-link-probe logout --state <dir>
          shellx-link-probe watch --state <dir> [--machine <id>] [--seconds <n>] [--recheck]
          shellx-link-probe sessions --state <dir> [--machine <id>]
          shellx-link-probe workspaces --state <dir> [--machine <id>] [--seconds <n>]
          shellx-link-probe workspace-create --state <dir> [--machine <id>]
          shellx-link-probe workspace-rename <workspace_id> <title> --state <dir> [--machine <id>]
          shellx-link-probe workspace-close <workspace_id> --state <dir> [--machine <id>]
          shellx-link-probe approve <request_id> --state <dir> [--machine <id>] [--mode <mode>]
          shellx-link-probe answer <request_id> --state <dir> [--machine <id>] --select <label> [--select <label>]...
          shellx-link-probe plan <request_id> --state <dir> [--machine <id>] --mode <plan mode> [--feedback-file <file>]
          shellx-link-probe chat-history <session_id> --state <dir> [--machine <id>] [--limit <n>] [--before <seq>]
          shellx-link-probe chat-send <session_id> --state <dir> [--machine <id>] --text-file <file>
          shellx-link-probe chat-stop <session_id> --state <dir> [--machine <id>] [--hard]
          shellx-link-probe agent-close <session_id> --state <dir> [--machine <id>]
          shellx-link-probe terminal-close <workspace_id> <terminal_id> --state <dir> [--machine <id>]
          shellx-link-probe terminal-view <terminal_id> --state <dir> [--machine <id>] [--cols <n>] [--rows <n>] [--seconds <n>]
          shellx-link-probe terminal-type <terminal_id> --state <dir> [--machine <id>] [--cols <n>] [--rows <n>] [--text <text>] [--key <key>]... [--paste-file <file>] [--wait-ms <n>] [--dry-run]
          shellx-link-probe terminal-create <workspace_id> --state <dir> [--machine <id>]
          shellx-link-probe bench --state <dir> [--machine <id>] --socket <path> [--count <n>] [--mode <mode>]

        --state is a directory only you can read (created 0700 when missing); keep it outside any
        repository. It holds phone.key (the Link static key), session.json (the relay token) and
        machines.json (paired machines with their host keys), each 0600.
        login reads the password from stdin. pair reads the QR's URI from --offer-file, which must
        be 0600: the raw shellx-link://pair URI, or the JSON reply of shellx.link.debug_pairing_offer.
        --machine may be left out when exactly one machine is paired.
        <mode> is once (default), always, all or deny. <plan mode> is manual, auto_accept,
        ultraplan or deny.
        answer takes one --select per question, in order: an option's label picks that option,
        any other text is a free-text answer; join the labels of a multi-select question with ", ".
        workspaces logs the Mac's workspaces (with their terminals), then every change until the session
        ends (exit 4) or --seconds pass (exit 0). workspace-create makes a workspace in a directory the
        Mac chooses; workspace-rename and workspace-close take the workspace_id from that list. They exit 2
        unless the Mac answers ok.
        agent-close closes the terminal a live agent runs in on the Mac (the whole workspace when it is the
        workspace's last tab of any kind); take the session_id from sessions. It exits 2 unless the Mac answers ok.
        terminal-close closes one terminal tab of a workspace on the Mac (the whole workspace when it is the
        workspace's last tab); take both ids from workspaces. It exits 2 unless the Mac answers ok.
        terminal-view opens a view of a terminal (take the id from workspaces) at --cols x --rows (80 x 24 when left
        out), logs every frame it applies and prints the screen after each snapshot and when it stops, until the view
        or its session ends (exit 4) or --seconds pass (exit 0). terminal-type opens a view, waits for its first snapshot,
        sends one input message (the --paste-file text, then --text, then each --key in order), logs the time until the
        next frame (the echo), waits --wait-ms (1000 when left out), prints the screen and closes the view. A key is a
        name (enter, tab, backspace, escape, delete, space, up, down, left, right, home, end, page_up, page_down, a to z)
        after any of ctrl, alt and shift joined with +, like ctrl+c or shift+tab. With --dry-run it prints the
        terminal.view.input message instead of connecting. terminal-create opens a terminal tab in a workspace without
        changing what the Mac shows; it exits 2 unless the Mac answers ok. All three exit 3 when the Mac does not offer
        the feature (terminal_view, terminal_create).
        watch logs pending requests, session states and chat entries until the session ends
        (exit 4) or --seconds pass (exit 0). With --recheck it then tries to connect again twice:
        with a ticket minted before the end (the Mac's handshake check) and with a new ticket (the
        relay grant).
        bench sends fake blocking Claude PermissionRequest hooks (feed.push) to the Mac app's control
        socket and answers them from the phone side. The app must accept processes it did not start
        (a DEBUG build launched with CMUX_SOCKET_MODE=allowAll).
        """

    static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else { throw ProbeError(usage) }
        let args = try Arguments(Array(arguments.dropFirst()))
        switch command {
        case "login":
            try args.expect(positional: 0, options: ["state", "api", "email", "password-stdin", "device-name"])
            try await Account.login(args)
        case "pair":
            try args.expect(positional: 0, options: ["state", "offer-file"])
            try await Account.pair(args)
        case "machines":
            try args.expect(positional: 0, options: ["state"])
            try await Account.machines(args)
        case "unpair":
            try args.expect(positional: 0, options: ["state", "machine"])
            try await Account.unpair(args)
        case "logout":
            try args.expect(positional: 0, options: ["state"])
            try await Account.logout(args)
        case "watch":
            try args.expect(positional: 0, options: ["state", "machine", "seconds", "recheck"])
            try await Watch.run(args)
        case "sessions":
            try args.expect(positional: 0, options: ["state", "machine"])
            try await Commands.sessions(args)
        case "workspaces":
            try args.expect(positional: 0, options: ["state", "machine", "seconds"])
            try await Commands.workspaces(args)
        case "workspace-create":
            try args.expect(positional: 0, options: ["state", "machine"])
            try await Commands.workspaceCreate(args)
        case "workspace-rename":
            try args.expect(positional: 2, options: ["state", "machine"])
            try await Commands.workspaceRename(args)
        case "workspace-close":
            try args.expect(positional: 1, options: ["state", "machine"])
            try await Commands.workspaceClose(args)
        case "approve":
            try args.expect(positional: 1, options: ["state", "machine", "mode"])
            try await Commands.approve(args)
        case "answer":
            try args.expect(positional: 1, options: ["state", "machine", "select"], repeatable: ["select"])
            try await Commands.answer(args)
        case "plan":
            try args.expect(positional: 1, options: ["state", "machine", "mode", "feedback-file"])
            try await Commands.plan(args)
        case "chat-history":
            try args.expect(positional: 1, options: ["state", "machine", "limit", "before"])
            try await Commands.chatHistory(args)
        case "chat-send":
            try args.expect(positional: 1, options: ["state", "machine", "text-file"])
            try await Commands.chatSend(args)
        case "chat-stop":
            try args.expect(positional: 1, options: ["state", "machine", "hard"])
            try await Commands.chatStop(args)
        case "agent-close":
            try args.expect(positional: 1, options: ["state", "machine"])
            try await Commands.agentClose(args)
        case "terminal-close":
            try args.expect(positional: 2, options: ["state", "machine"])
            try await Commands.terminalClose(args)
        case "terminal-view":
            try args.expect(positional: 1, options: ["state", "machine", "cols", "rows", "seconds"])
            try await TerminalCommands.view(args)
        case "terminal-type":
            try args.expect(
                positional: 1,
                options: ["state", "machine", "cols", "rows", "text", "key", "paste-file", "wait-ms", "dry-run"],
                repeatable: ["key"])
            try await TerminalCommands.type(args)
        case "terminal-create":
            try args.expect(positional: 1, options: ["state", "machine"])
            try await TerminalCommands.create(args)
        case "bench":
            try args.expect(positional: 0, options: ["state", "machine", "socket", "count", "mode"])
            try await Bench(args: args).run()
        case "help", "-h", "--help":
            print(usage)
        default:
            // Never echoed: a mistyped command could be a pasted secret.
            throw ProbeError("unknown command\n\(usage)")
        }
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
_ = Log.started   // log times count from launch
do {
    try await Probe.run(Array(CommandLine.arguments.dropFirst()))
    exit(0)
} catch let status as ExitStatus {
    exit(status.code)
} catch {
    FileHandle.standardError.write(Data("shellx-link-probe: \(ErrorText.describe(error))\n".utf8))
    exit(1)
}
