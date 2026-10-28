import Foundation
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkSession

extension Probe {
    static let clientVersion = "shellx-link-probe/2"
    static let deviceName = "shellx-link-probe"
}

/// Opens a Link session to a paired machine with a ticket the probe mints itself.
enum Session {
    struct Opened {
        let client: LinkClient
        let machine: PairedMachine
        let api: RelayAPI
        let token: String
        let key: NoiseStaticKey
    }

    static func open(_ args: Arguments) async throws -> Opened {
        let state = try ProbeState.open(args)
        let session = try state.loadSession()
        let key = try state.loadKey()
        let machine = try state.machine(args)
        let api = try session.relayAPI()
        let started = ContinuousClock.now
        let client = try await LinkConnector.connect(
            machine: machine, key: key, api: api, token: session.token, clientVersion: Probe.clientVersion,
            deviceName: Probe.deviceName)
        Log.line(
            "connected to \"\(Log.shown(machine.name))\": ticket + circuit + Noise + hello/welcome"
                + " \(Stats.format(Stats.ms(ContinuousClock.now - started))) ms")
        return Opened(client: client, machine: machine, api: api, token: session.token, key: key)
    }
}

/// The one-shot session commands.
enum Commands {
    static func sessions(_ args: Arguments) async throws {
        let client = try await Session.open(args).client
        let list = try await client.sessions()
        Log.line("sessions revision=\(list.revision) count=\(list.sessions.count)")
        for session in list.sessions { Log.session(session) }
        await client.close()
    }

    /// Logs the workspace list, then every change until the session ends (exit 4) or `--seconds` pass (exit 0).
    static func workspaces(_ args: Arguments) async throws {
        let seconds = try args.optionalInt("seconds")
        let client = try await Session.open(args).client
        Log.line("host features: \(client.hostFeatures.sorted().map { Log.shown($0) })")
        var revision = try await logWorkspaces(client)
        let closedByTimer = Flag()
        let timer = seconds.map { seconds in
            Task {
                try await Task.sleep(for: .seconds(seconds))
                closedByTimer.set()
                Log.line("workspaces: \(seconds) s elapsed, closing")
                await client.close()
            }
        }
        defer { timer?.cancel() }
        for await change in client.workspaceChanges {
            if change.revision <= revision { continue }   // already in the list
            if change.revision != revision + 1 {
                Log.line("workspaces revision gap: had \(revision), got \(change.revision); resyncing")
                revision = try await logWorkspaces(client)
                continue
            }
            revision = change.revision
            Log.line(
                "workspaces changed revision=\(change.revision) upserted=\(change.upserted.count)"
                    + " removed=\(change.removed.map { Log.shown($0) })")
            for workspace in change.upserted { Log.workspace(workspace) }
        }
        if !closedByTimer.isSet {
            Log.line("workspaces: session ended at \(Log.wallClock()) (ended by the Mac or the relay)")
            throw ExitStatus(code: 4)
        }
    }

    private static func logWorkspaces(_ client: LinkClient) async throws -> Int {
        let list = try await client.workspaces()
        Log.line("workspaces revision=\(list.revision) count=\(list.workspaces.count)")
        for workspace in list.workspaces { Log.workspace(workspace) }
        return list.revision
    }

    static func workspaceCreate(_ args: Arguments) async throws {
        let client = try await Session.open(args).client
        let started = ContinuousClock.now
        let result = try await client.createWorkspace()
        Log.line(
            "workspace.create outcome=\(Log.shown(result.outcome.wire))"
                + (result.workspaceId.map { " workspace=\(Log.shown($0))" } ?? "")
                + " rtt=\(Stats.format(Stats.ms(ContinuousClock.now - started))) ms")
        await client.close()
        if result.outcome != .ok { throw ExitStatus(code: 2) }
    }

    static func workspaceRename(_ args: Arguments) async throws {
        let workspaceId = args.positional[0]
        let title = args.positional[1]
        let client = try await Session.open(args).client
        let started = ContinuousClock.now
        let outcome = try await client.renameWorkspace(workspaceId: workspaceId, title: title)
        Log.line(
            "workspace.rename \(Log.shown(workspaceId)) \"\(Log.short(title))\" outcome=\(Log.shown(outcome.wire))"
                + " rtt=\(Stats.format(Stats.ms(ContinuousClock.now - started))) ms")
        await client.close()
        if outcome != .ok { throw ExitStatus(code: 2) }
    }

    static func workspaceClose(_ args: Arguments) async throws {
        let workspaceId = args.positional[0]
        let client = try await Session.open(args).client
        let started = ContinuousClock.now
        let outcome = try await client.closeWorkspace(workspaceId: workspaceId)
        Log.line(
            "workspace.close \(Log.shown(workspaceId)) outcome=\(Log.shown(outcome.wire))"
                + " rtt=\(Stats.format(Stats.ms(ContinuousClock.now - started))) ms")
        await client.close()
        if outcome != .ok { throw ExitStatus(code: 2) }
    }

    static func approve(_ args: Arguments) async throws {
        try await reply(args, decision: .permission(try args.permissionMode()))
    }

    static func answer(_ args: Arguments) async throws {
        let selections = args.all("select")
        guard !selections.isEmpty else { throw ProbeError("answer needs one --select per question") }
        try await reply(args, decision: .question(selections: selections))
    }

    static func plan(_ args: Arguments) async throws {
        let mode = ExitPlanMode(wire: try args.required("mode"))
        guard [.manual, .autoAccept, .ultraplan, .deny].contains(mode) else {
            throw ProbeError("--mode must be manual, auto_accept, ultraplan or deny")
        }
        let feedback = try args.optional("feedback-file").map { try TextFile.read($0, flag: "feedback-file") }
        try await reply(args, decision: .exitPlan(mode, feedback: feedback))
    }

    private static func reply(_ args: Arguments, decision: LinkDecision) async throws {
        let requestId = args.positional[0]
        let client = try await Session.open(args).client
        let started = ContinuousClock.now
        let outcome = try await client.reply(requestId: requestId, decision: decision)
        let rtt = Stats.ms(ContinuousClock.now - started)
        Log.line(
            "reply \(Log.shown(requestId)) \(describe(decision)) outcome=\(Log.shown(outcome.wire))"
                + " rtt=\(Stats.format(rtt)) ms")
        await client.close()
        if outcome == .unknown { throw ExitStatus(code: 2) }
    }

    private static func describe(_ decision: LinkDecision) -> String {
        switch decision {
        case let .permission(mode): return "kind=permission mode=\(mode.wire)"
        case let .question(selections):
            return "kind=question selections=[\(selections.map { "\"\(Log.short($0))\"" }.joined(separator: ", "))]"
        case let .exitPlan(mode, feedback):
            return "kind=exit_plan mode=\(mode.wire)" + (feedback.map { " feedback=\"\(Log.short($0))\"" } ?? "")
        case let .other(kind): return "kind=\(kind)"
        }
    }

    static func chatHistory(_ args: Arguments) async throws {
        let sessionId = args.positional[0]
        let limit = try args.optionalInt("limit") ?? 20
        let before = try args.optionalInt("before")
        let client = try await Session.open(args).client
        let page = try await client.chatHistory(sessionId: sessionId, beforeSeq: before, limit: limit)
        Log.line("chat history \(Log.shown(sessionId)): \(page.entries.count) entries, has_more=\(page.hasMore)")
        for entry in page.entries { Log.entry(entry) }
        await client.close()
    }

    static func chatSend(_ args: Arguments) async throws {
        let sessionId = args.positional[0]
        let text = try TextFile.read(try args.required("text-file"), flag: "text-file")
        let client = try await Session.open(args).client
        let started = ContinuousClock.now
        let outcome = try await client.chatSend(sessionId: sessionId, text: text)
        Log.line(
            "chat.send \(Log.shown(sessionId)) \"\(Log.short(text))\" outcome=\(Log.shown(outcome.wire))"
                + " rtt=\(Stats.format(Stats.ms(ContinuousClock.now - started))) ms")
        await client.close()
        if outcome != .submitted { throw ExitStatus(code: 2) }
    }

    static func chatStop(_ args: Arguments) async throws {
        let sessionId = args.positional[0]
        let hard = args.flag("hard")
        let client = try await Session.open(args).client
        let started = ContinuousClock.now
        let outcome = try await client.chatInterrupt(sessionId: sessionId, hard: hard)
        Log.line(
            "chat.interrupt \(Log.shown(sessionId)) hard=\(hard) outcome=\(Log.shown(outcome.wire))"
                + " rtt=\(Stats.format(Stats.ms(ContinuousClock.now - started))) ms")
        await client.close()
        if outcome != .sent { throw ExitStatus(code: 2) }
    }
}

/// A UTF-8 text file given by a flag (`--text-file`, `--feedback-file`), without one trailing newline.
enum TextFile {
    static func read(_ path: String, flag: String) throws -> String {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ProbeError("cannot read the --\(flag) file")
        }
        guard var text = String(data: data, encoding: .utf8) else { throw ProbeError("the --\(flag) file is not UTF-8") }
        if text.hasSuffix("\n") { text.removeLast() }
        guard !text.isEmpty else { throw ProbeError("the --\(flag) file is empty") }
        return text
    }
}
