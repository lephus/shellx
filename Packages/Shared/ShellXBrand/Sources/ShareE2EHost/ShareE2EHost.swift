// Test-only host for scripts/shellx/share-e2e.mjs: one `ShareHost` over a scripted source.
//
// Usage: share-e2e-host --api <base> --token <desktop token> --id <share id> --slot <slot>
//                       --secret <base64url> --perm view|type [--expires-at <unix>]
// stdin:  `stop <revoked|expired|host_quit>` | `stats`
// stdout: one JSON object per line: {"event":"started"|"registered"|"viewers"|"stats"|"stopped", ...}
import Foundation
import os
import ShellXRemoteCore

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("share-e2e-host: \(message)\n".utf8))
    exit(2)
}

/// Sinks per pane; reached from the main actor (subscribe/input) and token deinit (any thread).
final class SinkRegistry: Sendable {
    private let sinks = OSAllocatedUnfairLock(initialState: [Int: (pane: String, sink: @Sendable (Data) -> Void)]())
    private let next = OSAllocatedUnfairLock(initialState: 0)

    func add(pane: String, _ sink: @escaping @Sendable (Data) -> Void) -> Int {
        let id = next.withLock { $0 += 1; return $0 }
        sinks.withLock { $0[id] = (pane, sink) }
        return id
    }

    func remove(_ id: Int) { sinks.withLock { _ = $0.removeValue(forKey: id) } }

    func send(pane: String, _ data: Data) {
        let targets = sinks.withLock { $0.values.filter { $0.pane == pane }.map(\.sink) }
        for sink in targets { sink(data) }
    }
}

final class SinkToken: Sendable {
    private let registry: SinkRegistry
    private let id: Int
    init(registry: SinkRegistry, id: Int) { self.registry = registry; self.id = id }
    deinit { registry.remove(id) }
}

/// Fixed panes: a terminal `p1` (80x24) that echoes typed input as output, and a browser placeholder.
@MainActor
final class ScriptedSource: ShareSource {
    static let banner = "\u{1b}[H\u{1b}[2Jshare-e2e scripted pane\r\n$ "
    let registry = SinkRegistry()
    var onPanesChanged: (() -> Void)?
    let panes = [
        SharePane(id: "p1", title: "zsh", kind: .terminal, cols: 80, rows: 24),
        SharePane(id: "b1", title: "Docs", kind: .browser, cols: 0, rows: 0),
    ]
    var activePane: String? { "p1" }

    func snapshot(pane: String) -> (cols: Int, rows: Int, vt: Data)? {
        pane == "p1" ? (80, 24, Data(Self.banner.utf8)) : nil
    }

    func subscribe(pane: String, _ sink: @escaping @Sendable (Data) -> Void) -> AnyObject {
        SinkToken(registry: registry, id: registry.add(pane: pane, sink))
    }

    func input(pane: String, _ bytes: Data) {
        emit(["event": "input", "pane": pane, "bytes": bytes.count])
        registry.send(pane: pane, bytes)
    }
}

/// `POST <api>/v2/shares/<id>/host-ticket` with the desktop token.
struct HTTPShareTickets: ShareTicketProvider {
    let api: URL
    let token: String

    func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date) {
        var request = URLRequest(url: api.appendingPathComponent("v2/shares/\(shareID)/host-ticket"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ticket = body["ticket"] as? String,
              let relay = (body["relay_url"] as? String).flatMap(URL.init(string:)),
              let expires = body["expires_at_unix"] as? Int
        else {
            emit(["event": "host_ticket_failed", "status": status])
            throw URLError(.badServerResponse)
        }
        emit(["event": "host_ticket"])
        return (ticket, relay, Date(timeIntervalSince1970: TimeInterval(expires)))
    }
}

/// Real sockets; reports the relay's `registered` reply so the harness knows the slot is live.
struct ObservedSockets: ShareSocketFactory {
    let inner = URLSessionShareSocketFactory()

    func open(_ url: URL) async throws -> any ShareSocket {
        ObservedSocket(inner: try await inner.open(url))
    }
}

/// A class, like the real socket: ShareHost tells circuits apart by serial number, not socket identity.
final class ObservedSocket: ShareSocket {
    let inner: any ShareSocket
    init(inner: any ShareSocket) { self.inner = inner }
    func send(text: String) async throws {
        if ProcessInfo.processInfo.environment["SHARE_E2E_DEBUG"] != nil { emit(["event": "debug_send", "text": text]) }
        try await inner.send(text: text)
    }
    func send(data: Data) async throws {
        if ProcessInfo.processInfo.environment["SHARE_E2E_DEBUG"] != nil { emit(["event": "debug_send", "binary": data.count]) }
        try await inner.send(data: data)
    }
    func close() { inner.close() }
    func receive() async throws -> ShareSocketMessage {
        let message = try await inner.receive()
        if ProcessInfo.processInfo.environment["SHARE_E2E_DEBUG"] != nil {
            switch message {
            case .text(let text): emit(["event": "debug_recv", "text": text])
            case .data(let data): emit(["event": "debug_recv", "binary": data.count])
            }
        }
        if case .text(let text) = message, let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = object["type"] as? String, type == "registered" || type == "error" {
            emit(["event": type == "registered" ? "registered" : "relay_error", "code": object["code"] as? String ?? ""])
        }
        return message
    }
}

@main
struct ShareE2EHost {
    static func main() async {
        var args: [String: String] = [:]
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let key = it.next() {
            guard key.hasPrefix("--"), let value = it.next() else { fail("bad argument \(key)") }
            args[String(key.dropFirst(2))] = value
        }
        guard let api = args["api"].flatMap(URL.init(string:)), let token = args["token"], let id = args["id"],
              let slot = args["slot"], let secret = args["secret"].flatMap(ShareSecret.init(base64url:)),
              let perm = args["perm"].flatMap(SharePermission.init(rawValue:))
        else { fail("missing or invalid arguments") }
        let expiresAt = args["expires-at"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))

        let source = ScriptedSource()
        let host = ShareHost(shareID: id, slot: slot, secret: secret, permission: perm, expiresAt: expiresAt,
                             source: source, tickets: HTTPShareTickets(api: api, token: token), sockets: ObservedSockets())
        Task {
            for await viewers in host.viewerStream {
                emit(["event": "viewers", "labels": viewers.map(\.label)])
            }
            emit(["event": "stopped"])
        }
        await host.start()
        emit(["event": "started"])

        // Blocking reads on a plain thread: the main actor must stay free for the ShareSource.
        let (lines, sink) = AsyncStream.makeStream(of: String.self)
        Thread.detachNewThread {
            while let line = readLine() { sink.yield(line) }
            sink.finish()
        }
        for await line in lines {
            let words = line.split(separator: " ").map(String.init)
            switch words.first {
            case "stats":
                emit(["event": "stats", "dropped_input": await host.droppedInputCount,
                      "dropped_frames": await host.droppedFrameCount])
            case "stop":
                let reason = words.count > 1 ? ShareByeReason(rawValue: words[1]) ?? .hostQuit : .hostQuit
                await host.stop(reason: reason)
                try? await Task.sleep(for: .milliseconds(100))
                emit(["event": "exit"])
                exit(0)
            default:
                emit(["event": "unknown_command"])
            }
        }
        await host.stop(reason: .hostQuit)
    }
}
