import Foundation
import os
import ShellXLinkCore
import ShellXLinkRelay

/// Keep-alive timing of a session. Tests shorten it; production uses `standard`.
struct LinkTimings: Sendable {
    /// How often an established session sends `ping`.
    var pingInterval: Duration
    /// A session that has received nothing for this long is dead and its circuit is closed.
    var idleTimeout: Duration
    /// How long `LinkClient.snapshot()` and `reply()` wait for their answer.
    var requestTimeout: Duration = .seconds(10)

    static let standard = LinkTimings(pingInterval: .seconds(20), idleTimeout: .seconds(45))
}

let linkLog = Logger(subsystem: "pro.shellx.link", category: "session")

/// Wraps a circuit and remembers when a frame last arrived, so a watchdog can close a dead one.
///
/// A pending `receive()` is never cancelled to enforce a timeout, because cancelling it kills a
/// relay circuit. The watchdog closes the circuit instead, and the blocked `receive()` then
/// throws `RelayError.closed`.
final class WatchedCircuit: RelayCircuit, @unchecked Sendable {
    private let inner: any RelayCircuit
    private let lock = NSLock()
    private var lastReceive = ContinuousClock.now

    init(_ inner: any RelayCircuit) {
        self.inner = inner
    }

    func send(_ data: Data) async throws {
        try await inner.send(data)
    }

    func receive() async throws -> Data {
        let frame = try await inner.receive()
        lock.withLock { lastReceive = .now }
        return frame
    }

    func close() async {
        await inner.close()
    }

    /// Closes the circuit once nothing has arrived for `idleTimeout`. Returns after closing it or
    /// when the calling task is cancelled.
    func watch(idleTimeout: Duration) async {
        let step = idleTimeout / 5
        while !Task.isCancelled {
            let idle = lock.withLock { ContinuousClock.now - lastReceive }
            if idle >= idleTimeout {
                linkLog.info("closing a session that was silent for \(idleTimeout, privacy: .public)")
                await inner.close()
                return
            }
            try? await Task.sleep(for: step)
        }
    }
}

/// Sends `ping` every `interval` until the task is cancelled or a send fails.
func runPings(on channel: SecureChannel, every interval: Duration) async {
    var nonce = UInt64.random(in: 0...UInt64.max)
    while true {
        do {
            try await Task.sleep(for: interval)
        } catch {
            return
        }
        nonce &+= 1
        do {
            try await channel.send(.ping(nonce: nonce))
        } catch {
            return
        }
    }
}
