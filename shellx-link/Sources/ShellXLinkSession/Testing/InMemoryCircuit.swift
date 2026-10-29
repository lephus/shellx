import Foundation
import ShellXLinkRelay

/// Returns the two ends of a connected in-memory circuit, for tests and local probes.
///
/// It behaves like a relay circuit:
/// - frames arrive in order, one `send` per `receive`;
/// - `close()` on either end ends the circuit for both: pending and future `receive()` calls
///   throw `RelayError.closed`, and so does `send`. Frames the peer sent before the close are
///   still delivered to the other end first, as a relay delivers them before it reports the
///   disconnect; the closing end drops its own unread frames, as a closed socket does;
/// - cancelling a pending `receive()` closes the circuit, as it closes the relay WebSocket.
public func makeInMemoryCircuitPair() -> (any RelayCircuit, any RelayCircuit) {
    let pipe = InMemoryPipe()
    return (InMemoryCircuit(pipe: pipe, side: 0), InMemoryCircuit(pipe: pipe, side: 1))
}

final class InMemoryCircuit: RelayCircuit {
    private let pipe: InMemoryPipe
    private let side: Int

    init(pipe: InMemoryPipe, side: Int) {
        self.pipe = pipe
        self.side = side
    }

    func send(_ data: Data) async throws {
        try pipe.send(data, from: side)
    }

    func receive() async throws -> Data {
        try await pipe.receive(side: side)
    }

    func close() async {
        pipe.close(from: side)
    }
}

/// Shared state of both ends. `side` is 0 or 1; each side has an inbox and at most one waiter.
final class InMemoryPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var inboxes: [[Data]] = [[], []]
    private var waiters: [CheckedContinuation<Data, any Error>?] = [nil, nil]

    func send(_ data: Data, from side: Int) throws {
        let destination = 1 - side
        lock.lock()
        guard !closed else {
            lock.unlock()
            throw RelayError.closed
        }
        if let waiter = waiters[destination] {
            waiters[destination] = nil
            lock.unlock()
            waiter.resume(returning: data)
            return
        }
        inboxes[destination].append(data)
        lock.unlock()
    }

    func receive(side: Int) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
                lock.lock()
                if !inboxes[side].isEmpty {
                    let frame = inboxes[side].removeFirst()
                    lock.unlock()
                    continuation.resume(returning: frame)
                } else if closed {
                    lock.unlock()
                    continuation.resume(throwing: RelayError.closed)
                } else if waiters[side] != nil {
                    lock.unlock()
                    continuation.resume(throwing: RelayError.protocolViolation("concurrent receive on one end"))
                } else {
                    waiters[side] = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            // A relay circuit closes its WebSocket when a pending receive is cancelled.
            close(from: side)
        }
    }

    func close(from side: Int) {
        lock.lock()
        closed = true
        inboxes[side].removeAll()
        let pending = waiters.compactMap { $0 }
        waiters = [nil, nil]
        lock.unlock()
        for waiter in pending { waiter.resume(throwing: RelayError.closed) }
    }
}
