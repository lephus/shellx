// shellx-link-probe: plays the phone for the ShellX Link P1 spike.
//
// It connects to a Mac's link slot through the relay with a `shellx.link.debug_invite` reply,
// then lists, watches and answers the Mac's pending agent requests, and measures latency.
// It never prints the relay ticket, the private key or the invite's contents.

import Darwin
import Foundation
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession

enum Probe {
    static let usage = """
        usage:
          shellx-link-probe keygen --out <file>
          shellx-link-probe snapshot --invite <file|-> --key <file>
          shellx-link-probe watch --invite <file|-> --key <file> [--seconds <n>]
          shellx-link-probe approve <request_id> --invite <file|-> --key <file> [--mode <mode>]
          shellx-link-probe bench --count <n> --invite <file|-> --key <file> --socket <path> [--mode <mode>]

        <mode> is once (default), always, all or deny.
        --invite is a file holding the shellx.link.debug_invite reply, or - for stdin. The invite
        carries a relay ticket: keep it out of the command line, and keep the file private (0600).
        --socket is the Mac app's control socket; bench sends fake blocking Claude
        PermissionRequest hooks (feed.push) to it and answers them from the phone side. The app
        must accept processes it did not start (a DEBUG build launched with CMUX_SOCKET_MODE=allowAll).
        """

    static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else { throw ProbeError(usage) }
        let args = try Arguments(Array(arguments.dropFirst()))
        switch command {
        case "keygen":
            try args.expect(positional: 0, options: ["out"])
            let key = try KeyFile.create(at: try args.required("out"))
            print(key.publicKey.base64EncodedString())
        case "snapshot":
            try args.expect(positional: 0, options: ["invite", "key"])
            try await snapshot(args)
        case "watch":
            try args.expect(positional: 0, options: ["invite", "key", "seconds"])
            try await watch(args)
        case "approve":
            try args.expect(positional: 1, options: ["invite", "key", "mode"])
            try await approve(args)
        case "bench":
            try args.expect(positional: 0, options: ["invite", "key", "socket", "count", "mode"])
            try await Bench(args: args).run()
        case "help", "-h", "--help":
            print(usage)
        default:
            // Never echoed: a pasted invite would print its ticket.
            throw ProbeError("unknown command\n\(usage)")
        }
    }

    // MARK: - Commands

    static func snapshot(_ args: Arguments) async throws {
        let client = try await Session.open(args)
        let snapshot = try await client.snapshot()
        Log.line("snapshot revision=\(snapshot.revision) pending=\(snapshot.pending.count)")
        for item in snapshot.pending { Log.item(item) }
        await client.close()
    }

    static func watch(_ args: Arguments) async throws {
        let seconds = try args.optionalInt("seconds")
        let client = try await Session.open(args)
        if let seconds {
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                Log.line("watch: \(seconds) s elapsed, closing")
                await client.close()
            }
        }
        var current = try await client.snapshot()
        Log.line("snapshot revision=\(current.revision) pending=\(current.pending.count)")
        for item in current.pending { Log.item(item) }
        for await change in client.changes {
            if change.revision <= current.revision { continue }   // already in the snapshot
            if change.revision != current.revision + 1 {
                Log.line("revision gap: had \(current.revision), got \(change.revision); resyncing")
                current = try await client.snapshot()
                Log.line("snapshot revision=\(current.revision) pending=\(current.pending.count)")
                for item in current.pending { Log.item(item) }
                continue
            }
            current.revision = change.revision
            Log.line("changed revision=\(change.revision) added=\(change.added.count) resolved=\(change.resolved)")
            for item in change.added { Log.item(item) }
        }
        Log.line("watch: session ended")
    }

    static func approve(_ args: Arguments) async throws {
        let requestId = args.positional[0]
        let mode = try args.mode()
        let client = try await Session.open(args)
        let started = ContinuousClock.now
        let outcome = try await client.reply(requestId: requestId, mode: mode)
        let rtt = Stats.ms(ContinuousClock.now - started)
        Log.line("reply \(requestId) mode=\(mode.rawValue) outcome=\(outcome.rawValue) rtt=\(Stats.format(rtt)) ms")
        await client.close()
        if outcome == .unknown { throw ExitStatus(code: 2) }
    }
}

// MARK: - Session

enum Session {
    static let clientVersion = "shellx-link-probe/1"

    /// Reads `--invite` and `--key`, opens a relay circuit to the invite's slot and runs the
    /// handshake and `hello`. A retryable relay refusal (`slot-offline` while the host re-registers)
    /// is retried a few times.
    static func open(_ args: Arguments) async throws -> LinkClient {
        let key = try KeyFile.load(try args.required("key"))
        let invite = try Invite.read(try args.required("invite"))
        var attempt = 0
        while true {
            do {
                let started = ContinuousClock.now
                let circuit = try await RelayClientConnector.connect(
                    relayURL: invite.relayURL, slot: invite.slot, ticket: invite.ticket)
                let joined = ContinuousClock.now
                let client = try await LinkClient.connect(
                    circuit, key: key, hostKey: invite.hostKey, clientVersion: clientVersion,
                    deviceName: "shellx-link-probe")
                let ready = ContinuousClock.now
                Log.line(
                    "connected: circuit \(Stats.format(Stats.ms(joined - started))) ms, "
                        + "noise + hello/welcome \(Stats.format(Stats.ms(ready - joined))) ms")
                return client
            } catch RelayError.server(let code, let retryable) where retryable && attempt < 5 {
                attempt += 1
                Log.line("relay refused (\(code)), retrying \(attempt)/5")
                try await Task.sleep(for: .milliseconds(400))
            }
        }
    }
}

/// The parts of a `shellx.link.debug_invite` reply the probe needs. Never printed.
struct Invite {
    let relayURL: URL
    let slot: String
    let ticket: RelayTicket
    let hostKey: Data

    /// Reads the reply from `source` (a path, or `-` for stdin). Accepts the bare result object or
    /// the socket envelope `{"ok":true,"result":{...}}`. Errors name the flag, never its value.
    static func read(_ source: String) throws -> Invite {
        // The invite itself on the command line: its ticket would sit in the shell history and `ps`.
        guard source.drop(while: { $0.isWhitespace }).first != "{" else {
            throw ProbeError("--invite takes a file path or -, not the invite itself; save the reply to a 0600 file")
        }
        let data: Data
        if source == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            try PrivateFile.checkOwnerOnly(source, flag: "invite")
            guard let contents = FileManager.default.contents(atPath: source) else {
                throw ProbeError("cannot read the --invite file")
            }
            data = contents
        }
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProbeError("the invite is not a JSON object")
        }
        if let result = object["result"] as? [String: Any] { object = result }
        guard let relayText = object["relay_url"] as? String, let relayURL = URL(string: relayText),
              let slot = object["slot"] as? String, !slot.isEmpty,
              let ticket = object["ticket"] as? String, !ticket.isEmpty,
              let expires = (object["expires_at_unix"] as? NSNumber)?.int64Value,
              let hostKeyText = object["host_key_b64"] as? String,
              let hostKey = Data(base64Encoded: hostKeyText), hostKey.count == 32
        else {
            throw ProbeError("the invite lacks relay_url, slot, ticket, expires_at_unix or host_key_b64")
        }
        guard expires > Int64(Date().timeIntervalSince1970) else {
            throw ProbeError("the invite has expired; ask the Mac for a new one (shellx.link.debug_invite)")
        }
        return Invite(
            relayURL: relayURL, slot: slot, ticket: RelayTicket(ticket: ticket, expiresAtUnix: expires),
            hostKey: hostKey)
    }
}

/// The phone's Noise static key, stored as its 32 raw private bytes in an owner-only file.
enum KeyFile {
    /// Creates a new key at `path` (`--out`). Refuses to overwrite an existing file, and removes the
    /// file again when the key cannot be written in full.
    static func create(at path: String) throws -> NoiseStaticKey {
        let key = NoiseStaticKey()
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw ProbeError("cannot create the --out file: \(PrivateFile.errnoText())") }
        defer { close(fd) }
        let written = key.rawPrivate.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == key.rawPrivate.count else {
            let reason = written < 0 ? PrivateFile.errnoText() : "short write"
            unlink(path)   // a partial key file would only fail `load` later
            throw ProbeError("cannot write the --out file: \(reason)")
        }
        return key
    }

    static func load(_ path: String) throws -> NoiseStaticKey {
        try PrivateFile.checkOwnerOnly(path, flag: "key")
        guard let data = FileManager.default.contents(atPath: path), data.count == 32,
              let key = try? NoiseStaticKey(rawPrivate: data)
        else {
            throw ProbeError("the --key file is not a key file written by `shellx-link-probe keygen`")
        }
        return key
    }
}

enum PrivateFile {
    /// Refuses a secret file that its group or others can read. Errors name `--<flag>`, not the path.
    static func checkOwnerOnly(_ path: String, flag: String) throws {
        var info = stat()
        guard stat(path, &info) == 0 else { throw ProbeError("cannot read the --\(flag) file: \(errnoText())") }
        guard info.st_mode & 0o077 == 0 else {
            throw ProbeError("the --\(flag) file is readable by others; chmod 600 it")
        }
    }

    static func errnoText() -> String { String(cString: strerror(errno)) }
}

// MARK: - Bench

/// `bench`: for each of `count` requests, a fake Claude hook sends a blocking `feed.push`
/// PermissionRequest to the Mac's socket from this process, the phone side waits for it in
/// `agent.changed` and answers it, and the hook waits for the decision. All times use one clock.
struct Bench {
    let args: Arguments

    func run() async throws {
        let count = try args.optionalInt("count") ?? 50
        guard count > 0 else { throw ProbeError("--count must be positive") }
        let socketPath = try args.required("socket")
        let mode = try args.mode()
        let client = try await Session.open(args)
        let seen = Arrivals()
        let consumer = Task {
            for await change in client.changes {
                let at = ContinuousClock.now
                await seen.record(change: change, at: at)
            }
        }
        let start = try await client.snapshot()
        await seen.setRevision(start.revision)
        Log.line("bench: \(count) requests, mode \(mode.rawValue), start revision \(start.revision), pending \(start.pending.count)")

        let run = String(UUID().uuidString.prefix(8)).lowercased()
        let sessionId = "shellx-link-probe-\(run)"
        var changed: [Double] = []
        var replyRTT: [Double] = []
        var replyToHook: [Double] = []
        var failures = 0
        for index in 1...count {
            let requestId = "probe-\(run)-\(index)"
            let line = FakeHook.permissionRequest(requestId: requestId, sessionId: sessionId, index: index)
            let hook = Task { await FakeHook.send(line, socketPath: socketPath) }
            guard let seenAt = await seen.wait(for: .added(requestId), timeout: .seconds(10)) else {
                failures += 1
                Log.line("#\(index) FAIL: no agent.changed for the request within 10 s")
                _ = try? await client.reply(requestId: requestId, mode: .deny)
                let result = await hook.value
                Log.line("#\(index) hook ended: \(result.summary)")
                continue
            }
            let replyStarted = ContinuousClock.now
            let outcome: ReplyOutcome
            do {
                outcome = try await client.reply(requestId: requestId, mode: mode)
            } catch {
                failures += 1
                Log.line("#\(index) FAIL: agent.reply failed: \(ErrorText.describe(error))")
                _ = await hook.value
                continue
            }
            let replyAnswered = ContinuousClock.now
            let result = await hook.value
            let resolvedAt = await seen.wait(for: .resolved(requestId), timeout: .seconds(5))
            guard let sentAt = result.sentAt, let answeredAt = result.answeredAt else {
                failures += 1
                Log.line("#\(index) FAIL: hook \(result.summary)")
                continue
            }
            let ok = outcome == .delivered && result.status == "resolved" && result.mode == mode.rawValue
            let changedMs = Stats.ms(seenAt - sentAt)
            let rttMs = Stats.ms(replyAnswered - replyStarted)
            let hookMs = Stats.ms(answeredAt - replyStarted)
            // Only requests that worked count towards the latency figures; the rest are failures.
            if ok {
                changed.append(changedMs)
                replyRTT.append(rttMs)
                replyToHook.append(hookMs)
            } else {
                failures += 1
            }
            Log.line(
                "#\(index) \(ok ? "ok" : "FAIL") changed=\(Stats.format(changedMs)) ms"
                    + " reply_rtt=\(Stats.format(rttMs)) ms reply_to_hook=\(Stats.format(hookMs)) ms"
                    + " outcome=\(outcome.rawValue) hook=\(result.summary)"
                    + (resolvedAt == nil ? " (no resolved change within 5 s)" : ""))
            try await Task.sleep(for: .milliseconds(100))
        }
        let gaps = await seen.revisionGaps
        Log.line("bench: \(count - failures)/\(count) ok, revision gaps \(gaps)")
        Log.line("hook sent -> probe saw agent.changed:      \(Stats.summary(changed))")
        Log.line("agent.reply -> agent.reply.result (RTT):   \(Stats.summary(replyRTT))")
        Log.line("agent.reply sent -> hook got the decision: \(Stats.summary(replyToHook))")
        consumer.cancel()
        await client.close()
        if failures > 0 { throw ExitStatus(code: 3) }
    }
}

/// When each request id was first seen added or resolved in `agent.changed`.
actor Arrivals {
    enum Event: Hashable {
        case added(String)
        case resolved(String)
    }

    private var seen: [Event: ContinuousClock.Instant] = [:]
    private var waiters: [Event: CheckedContinuation<ContinuousClock.Instant?, Never>] = [:]
    private var revision: Int?
    private(set) var revisionGaps = 0

    /// The snapshot's revision. Never lowers the tracked one: the consumer, subscribed first, may
    /// already have recorded a later change.
    func setRevision(_ value: Int) {
        revision = max(revision ?? value, value)
    }

    func record(change: (revision: Int, added: [PendingItem], resolved: [String]), at instant: ContinuousClock.Instant) {
        if let revision, change.revision > revision + 1 { revisionGaps += 1 }
        if change.revision > (revision ?? Int.min) { revision = change.revision }
        for item in change.added { record(.added(item.requestId), at: instant) }
        for requestId in change.resolved { record(.resolved(requestId), at: instant) }
    }

    func wait(for event: Event, timeout: Duration) async -> ContinuousClock.Instant? {
        if let instant = seen[event] { return instant }
        return await withCheckedContinuation { continuation in
            waiters[event] = continuation
            Task {
                try? await Task.sleep(for: timeout)
                self.expire(event)
            }
        }
    }

    private func record(_ event: Event, at instant: ContinuousClock.Instant) {
        if seen[event] == nil { seen[event] = instant }
        waiters.removeValue(forKey: event)?.resume(returning: instant)
    }

    private func expire(_ event: Event) {
        waiters.removeValue(forKey: event)?.resume(returning: nil)
    }
}

/// A fake Claude `PermissionRequest` hook: the `feed.push` frame the ShellX CLI sends
/// (`shellx hooks feed --source claude`), written to the app's control socket, blocking until the
/// app answers with the decision.
enum FakeHook {
    struct Result: Sendable {
        var sentAt: ContinuousClock.Instant?
        var answeredAt: ContinuousClock.Instant?
        var status: String?
        var mode: String?
        var error: String?

        var summary: String {
            if let error { return "error: \(error)" }
            return "\(status ?? "?")/\(mode ?? "-")"
        }
    }

    static let waitSeconds = 60

    static func permissionRequest(requestId: String, sessionId: String, index: Int) -> Data {
        let event: [String: Any] = [
            "session_id": sessionId,
            "hook_event_name": "PermissionRequest",
            "_source": "claude",
            "_cmux_ordered_hook": true,
            "cwd": FileManager.default.currentDirectoryPath,
            "tool_name": "Bash",
            "tool_input": [
                "command": "echo shellx-link-probe \(index)",
                "description": "shellx-link-probe bench request \(index)",
            ],
            "_opencode_request_id": requestId,
        ]
        let frame: [String: Any] = [
            "id": UUID().uuidString,
            "method": "feed.push",
            "params": ["event": event, "wait_timeout_seconds": waitSeconds],
        ]
        var line = (try? JSONSerialization.data(withJSONObject: frame)) ?? Data("{}".utf8)
        line.append(0x0A)
        return line
    }

    static func send(_ line: Data, socketPath: String) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: blockingSend(line, socketPath: socketPath))
            }
        }
    }

    private static func blockingSend(_ line: Data, socketPath: String) -> Result {
        var result = Result()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { result.error = "socket: \(PrivateFile.errnoText())"; return result }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: waitSeconds + 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else { result.error = "socket path too long"; return result }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { result.error = "connect: \(PrivateFile.errnoText())"; return result }

        result.sentAt = ContinuousClock.now
        let wrote = line.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        guard wrote else { result.error = "write: \(PrivateFile.errnoText())"; return result }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !response.contains(0x0A) {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { result.error = n == 0 ? "socket closed" : "read: \(PrivateFile.errnoText())"; return result }
            response.append(contentsOf: buffer[0..<n])
        }
        result.answeredAt = ContinuousClock.now
        let firstLine = response.prefix(while: { $0 != 0x0A })
        guard let object = (try? JSONSerialization.jsonObject(with: firstLine)) as? [String: Any] else {
            result.error = "the app's answer is not JSON"
            return result
        }
        guard object["ok"] as? Bool == true, let payload = object["result"] as? [String: Any] else {
            let error = object["error"] as? [String: Any]
            result.error = "feed.push failed: \(error?["code"] as? String ?? "?")"
            return result
        }
        result.status = payload["status"] as? String
        result.mode = (payload["decision"] as? [String: Any])?["mode"] as? String
        return result
    }
}

// MARK: - Support

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]

    init(_ raw: [String]) throws {
        var index = 0
        while index < raw.count {
            let word = raw[index]
            if word.hasPrefix("--") {
                let name = String(word.dropFirst(2))
                // Errors echo only a plain option name: `--invite={...}` must not print the invite.
                guard Self.isPlainName(name) else {
                    throw ProbeError("malformed option: write --<name> <value>\n\(Probe.usage)")
                }
                guard index + 1 < raw.count else { throw ProbeError("--\(name) needs a value") }
                options[name] = raw[index + 1]
                index += 2
            } else {
                positional.append(word)
                index += 1
            }
        }
    }

    /// Lowercase ASCII letters, digits and `-`, like every option the probe takes.
    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    func expect(positional count: Int, options allowed: Set<String>) throws {
        guard positional.count == count else { throw ProbeError("wrong number of arguments\n\(Probe.usage)") }
        for name in options.keys where !allowed.contains(name) {
            throw ProbeError("unknown option --\(name)\n\(Probe.usage)")
        }
    }

    func required(_ name: String) throws -> String {
        guard let value = options[name], !value.isEmpty else { throw ProbeError("--\(name) is required") }
        return value
    }

    func optionalInt(_ name: String) throws -> Int? {
        guard let text = options[name] else { return nil }
        guard let value = Int(text) else { throw ProbeError("--\(name) must be a number") }
        return value
    }

    func mode() throws -> PermissionMode {
        guard let text = options["mode"] else { return .once }
        guard let mode = PermissionMode(rawValue: text) else {
            throw ProbeError("--mode must be once, always, all or deny")
        }
        return mode
    }
}

enum Stats {
    static func ms(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }

    static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Nearest-rank percentile.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }

    static func summary(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "no samples" }
        let sorted = values.sorted()
        return "n=\(sorted.count) p50 \(format(percentile(sorted, 0.5))) ms, p95 \(format(percentile(sorted, 0.95))) ms,"
            + " min \(format(sorted[0])) ms, max \(format(sorted[sorted.count - 1])) ms"
    }
}

enum Log {
    static let started = ContinuousClock.now

    /// One log line. Its text may carry request ids from the Mac or relay error codes, so it is
    /// printed through ``shown(_:)`` too.
    static func line(_ text: String) {
        let elapsed = Stats.ms(ContinuousClock.now - started) / 1000
        print("[+\(String(format: "%7.3f", elapsed))s] \(shown(text))")
    }

    /// Every field comes from the Mac and, through it, from the agent's tool input.
    static func item(_ item: PendingItem) {
        let preview = item.toolInputPreview.map { short($0) } ?? "-"
        print(
            "    pending \(shown(item.requestId)) kind=\(item.kind.rawValue) agent=\(shown(item.agent))"
                + " tool=\(item.toolName.map { shown($0) } ?? "-") workspace=\"\(short(item.workspaceTitle))\""
                + " preview=\(preview)")
    }

    /// `text` with every control character escaped: C0 (`\n`, `\r` and `\t` by name, the rest as
    /// `\u{..}`), DEL and C1, ESC and CSI among them. Text from the Mac, an agent or the relay
    /// therefore cannot move the cursor, recolor or retitle the terminal, or fake a log line.
    static func shown(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0x00...0x1F, 0x7F...0x9F: result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func short(_ text: String) -> String {
        let flat = shown(text)
        return flat.count > 160 ? String(flat.prefix(160)) + "…" : flat
    }
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct ExitStatus: Error {
    let code: Int32
}

enum ErrorText {
    /// A message safe to print: names the failure, never a ticket or key. Text the relay or the Mac
    /// sent goes through `Log.shown`.
    static func describe(_ error: any Error) -> String {
        if let probe = error as? ProbeError { return probe.description }
        if let relay = error as? RelayError {
            switch relay {
            case .closed: return "the relay circuit closed (does the Mac trust this key?)"
            case let .server(code, retryable):
                return "the relay refused: \(Log.shown(code))\(retryable ? " (retryable)" : "")"
            case let .protocolViolation(text): return "relay protocol violation: \(text)"
            }
        }
        if let noise = error as? NoiseError { return "Noise handshake failed: \(noise)" }
        if let link = error as? LinkClientError { return "link session: \(Log.shown(String(describing: link)))" }
        if let url = error as? URLError { return "network error \(url.code.rawValue)" }
        return "\(type(of: error))"
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
