import Foundation
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession

struct Arguments {
    /// Options that take no value.
    static let flags: Set<String> = ["password-stdin", "hard", "recheck"]

    var positional: [String] = []
    private var options: [String: [String]] = [:]
    private var flagsGiven: Set<String> = []

    init(_ raw: [String]) throws {
        var index = 0
        while index < raw.count {
            let word = raw[index]
            if word.hasPrefix("--") {
                let name = String(word.dropFirst(2))
                // Errors echo only a plain option name: `--offer=<uri>` must not print the URI.
                guard Self.isPlainName(name) else {
                    throw ProbeError("malformed option: write --<name> <value>\n\(Probe.usage)")
                }
                if Self.flags.contains(name) {
                    flagsGiven.insert(name)
                    index += 1
                    continue
                }
                guard index + 1 < raw.count else { throw ProbeError("--\(name) needs a value") }
                options[name, default: []].append(raw[index + 1])
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

    /// Checks the positional count and that every option given is allowed (and given once, unless
    /// it is `repeatable`).
    func expect(positional count: Int, options allowed: Set<String>, repeatable: Set<String> = []) throws {
        guard positional.count == count else { throw ProbeError("wrong number of arguments\n\(Probe.usage)") }
        for name in Set(options.keys).union(flagsGiven) where !allowed.contains(name) {
            throw ProbeError("unknown option --\(name)\n\(Probe.usage)")
        }
        for (name, values) in options where values.count > 1 && !repeatable.contains(name) {
            throw ProbeError("--\(name) is given more than once")
        }
    }

    func optional(_ name: String) -> String? { options[name]?.last }

    func all(_ name: String) -> [String] { options[name] ?? [] }

    func flag(_ name: String) -> Bool { flagsGiven.contains(name) }

    func required(_ name: String) throws -> String {
        guard let value = optional(name), !value.isEmpty else { throw ProbeError("--\(name) is required") }
        return value
    }

    func optionalInt(_ name: String) throws -> Int? {
        guard let text = optional(name) else { return nil }
        guard let value = Int(text) else { throw ProbeError("--\(name) must be a number") }
        return value
    }

    /// `--mode` of a permission answer; `once` when left out.
    func permissionMode() throws -> PermissionMode {
        guard let text = optional("mode") else { return .once }
        let mode = PermissionMode(wire: text)
        guard [.once, .always, .all, .deny].contains(mode) else {
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
        var text =
            "    pending \(shown(item.requestId)) kind=\(shown(item.kind.wire)) agent=\(shown(item.agent))"
            + " tool=\(item.toolName.map { shown($0) } ?? "-") workspace=\"\(short(item.workspaceTitle))\""
            + " modes=[\(item.modes.map { shown($0) }.joined(separator: ","))]"
        if let preview = item.toolInputPreview { text += " preview=\(short(preview))" }
        if let plan = item.planPreview { text += " plan=\"\(short(plan))\"" }
        print(text)
        for (index, question) in (item.questions ?? []).enumerated() {
            print(
                "      q\(index + 1) \(question.multiSelect ? "multi" : "single") \"\(short(question.prompt))\""
                    + " options=[\(question.options.map { "\"\(short($0.label))\"" }.joined(separator: ", "))]")
        }
    }

    static func session(_ session: AgentSession) {
        let since = session.stateSinceMs.map { " since=\(age($0))" } ?? ""
        print(
            "    session \(shown(session.sessionId)) agent=\(shown(session.agent)) state=\(shown(session.state.wire))"
                + "\(since) workspace=\"\(short(session.workspaceTitle))\""
                + (session.title.map { " title=\"\(short($0))\"" } ?? ""))
    }

    static func entry(_ entry: ChatEntry) {
        print(
            "    #\(entry.seq) \(shown(entry.role.wire))/\(shown(entry.kind.wire))"
                + (entry.toolName.map { "(\(shown($0)))" } ?? "") + " rev=\(entry.rev)"
                + (entry.truncated == true ? " truncated" : "") + ": \(short(entry.text))")
    }

    /// The local time of day with milliseconds, to line a probe event up with the Mac's log.
    static func wallClock() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    /// How long ago a Unix time in milliseconds was, like `12.3s ago`.
    private static func age(_ unixMs: Int64) -> String {
        let seconds = Date().timeIntervalSince1970 - Double(unixMs) / 1000
        return "\(Stats.format(seconds))s ago"
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

    /// `shown(text)`, cut to 160 characters.
    static func short(_ text: String) -> String {
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
    /// A message safe to print: names the failure, never a token, ticket or key. Text the relay or
    /// the Mac sent goes through `Log.shown`.
    static func describe(_ error: any Error) -> String {
        if let probe = error as? ProbeError { return probe.description }
        if let relay = error as? RelayError {
            switch relay {
            case .closed: return "the relay circuit closed (does the Mac trust this phone?)"
            case let .server(code, retryable):
                return "the relay refused: \(Log.shown(code))\(retryable ? " (retryable)" : "")"
            case let .protocolViolation(text): return "relay protocol violation: \(Log.shown(text))"
            case let .insecureTransport(scheme):
                return "refused to send a secret over plain \(Log.shown(scheme)) to a non-loopback host; use https/wss"
            }
        }
        if let api = error as? RelayAPIError {
            switch api {
            case let .http(status, code): return "the relay API answered \(status) \(Log.shown(code))"
            case .badResponse: return "the relay API answered something unexpected (or contradicting the QR)"
            case .slotMismatch: return "the relay minted a ticket for another slot than the paired one"
            case .notConnectTicket: return "the relay minted a ticket without the connect permission"
            }
        }
        if let pairing = error as? PhonePairingError {
            switch pairing {
            case .denied: return "the Mac denied the pairing"
            case .expired: return "the pairing request expired before the Mac allowed it"
            }
        }
        if let offer = error as? PairingOfferError {
            switch offer {
            case .badURI: return "the offer is not a shellx-link://pair URI"
            case .unsupportedVersion: return "the offer has an unsupported version"
            case let .badField(name): return "the offer's \(Log.shown(name)) field is malformed"
            }
        }
        if let noise = error as? NoiseError { return "Noise handshake failed: \(noise)" }
        if let link = error as? LinkClientError {
            switch link {
            case let .remote(code, message): return "the Mac answered error \(Log.shown(code)): \(Log.short(message))"
            case let .rejected(code, message): return "the Mac refused hello: \(Log.shown(code)): \(Log.short(message))"
            default: return "link session: \(Log.shown(String(describing: link)))"
            }
        }
        if let url = error as? URLError { return "network error \(url.code.rawValue)" }
        return "\(type(of: error))"
    }
}
