import Darwin
import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// `bench`: for each of `count` requests, a fake Claude hook sends a blocking `feed.push`
/// PermissionRequest to the Mac's socket from this process, the phone side (a session on a ticket the
/// probe minted itself) waits for it in `agent.changed` and answers it, and the hook waits for the
/// decision. All times use one clock.
struct Bench {
    let args: Arguments

    func run() async throws {
        let count = try args.optionalInt("count") ?? 50
        guard count > 0 else { throw ProbeError("--count must be positive") }
        let socketPath = try args.required("socket")
        let mode = try args.permissionMode()
        let client = try await Session.open(args).client
        let seen = Arrivals()
        let consumer = Task {
            for await change in client.changes {
                let at = ContinuousClock.now
                await seen.record(change: change, at: at)
            }
        }
        let start = try await client.snapshot()
        await seen.setRevision(start.revision)
        Log.line("bench: \(count) requests, mode \(mode.wire), start revision \(start.revision), pending \(start.pending.count)")

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
                _ = try? await client.reply(requestId: requestId, decision: .permission(.deny))
                let result = await hook.value
                Log.line("#\(index) hook ended: \(result.summary)")
                continue
            }
            let replyStarted = ContinuousClock.now
            let outcome: ReplyOutcome
            do {
                outcome = try await client.reply(requestId: requestId, decision: .permission(mode))
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
            let ok = outcome == .delivered && result.status == "resolved" && result.mode == mode.wire
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
                    + " outcome=\(outcome.wire) hook=\(result.summary)"
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

