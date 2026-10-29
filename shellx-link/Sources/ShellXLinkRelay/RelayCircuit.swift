import Foundation

/// One joined relay circuit: an ordered, bidirectional pipe of binary frames.
///
/// One `send` is one WebSocket binary message and arrives as one `receive` on the peer
/// (single framing). Call `receive` from one task at a time.
public protocol RelayCircuit: Sendable {
    func send(_ data: Data) async throws
    /// Returns the next frame. Throws `RelayError.closed` once the circuit has ended.
    func receive() async throws -> Data
    func close() async
}

/// A WebSocket to the relay. `URLSessionWebSocketTask` is thread-safe; this wrapper adds
/// cancellation (cancelling the waiting task closes the socket) and control-message codec.
final class RelaySocket: Sendable {
    private static let session = URLSession(configuration: .ephemeral)

    private let task: URLSessionWebSocketTask

    init(url: URL, bearer: String?) {
        var request = URLRequest(url: url)
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        task = Self.session.webSocketTask(with: request)
        task.resume()
    }

    func send(_ control: RelayControl) async throws {
        try await send(.string(try control.encodedText()))
    }

    func sendBinary(_ data: Data) async throws {
        try await send(.data(data))
    }

    private func send(_ message: URLSessionWebSocketTask.Message) async throws {
        let task = self.task
        try await withTaskCancellationHandler {
            try await task.send(message)
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        let task = self.task
        return try await withTaskCancellationHandler {
            try await task.receive()
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    /// Reads the next control message. Binary data before a circuit is ready is a violation.
    func receiveControl() async throws -> RelayControl {
        switch try await receive() {
        case .string(let text):
            return try RelayControl.decode(text)
        case .data:
            throw RelayError.protocolViolation("relay sent binary data before the circuit was ready")
        @unknown default:
            throw RelayError.protocolViolation("relay sent an unknown WebSocket message")
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// A ready circuit socket: binary messages are frames, text messages are relay control.
final class WebSocketRelayCircuit: RelayCircuit {
    private let socket: RelaySocket

    init(socket: RelaySocket) {
        self.socket = socket
    }

    func send(_ data: Data) async throws {
        do {
            try await socket.sendBinary(data)
        } catch {
            try Task.checkCancellation()
            throw RelayError.closed
        }
    }

    func receive() async throws -> Data {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                try Task.checkCancellation()
                throw RelayError.closed
            }
            switch message {
            case .data(let frame):
                return frame
            case .string(let text):
                switch try RelayControl.decode(text) {
                case .ping(let nonce):
                    try await socket.send(.pong(nonce: nonce))
                case .pong:
                    continue
                case let .error(code, _, retryable):
                    socket.close()
                    // The relay reports the other side leaving as an error; for this side it is
                    // the normal end of the circuit.
                    if code == "peer-disconnected" { throw RelayError.closed }
                    throw RelayError.server(code: code, retryable: retryable)
                default:
                    socket.close()
                    throw RelayError.protocolViolation("relay sent unexpected circuit control")
                }
            @unknown default:
                socket.close()
                throw RelayError.protocolViolation("relay sent an unknown WebSocket message")
            }
        }
    }

    func close() async {
        socket.close()
    }
}

/// Joins one side of an allocated circuit on its own WebSocket and waits for `ready`.
enum RelayCircuitJoin {
    static func join(
        endpoint: URL,
        slot: String,
        role: RelayRole,
        circuit: String,
        lane: String,
        generation: UInt64,
        ticket: String
    ) async throws -> WebSocketRelayCircuit {
        let socket = RelaySocket(url: RelayEndpoint.circuit(endpoint, circuit: circuit), bearer: ticket)
        do {
            try await socket.send(.join(
                protocol: RelayProtocol.version, slot: slot, circuit: circuit, lane: lane,
                generation: generation, ticket: ticket, role: role))
            try await withRelayTimeout(RelayProtocol.controlTimeout) {
                while true {
                    switch try await socket.receiveControl() {
                    case let .ready(readyCircuit, readyLane, readyGeneration)
                        where readyCircuit == circuit && readyLane == lane
                            && readyGeneration == generation:
                        return
                    case let .error(code, _, retryable):
                        throw RelayError.server(code: code, retryable: retryable)
                    case .ping(let nonce):
                        try await socket.send(.pong(nonce: nonce))
                    default:
                        continue
                    }
                }
            }
        } catch {
            socket.close()
            throw error
        }
        return WebSocketRelayCircuit(socket: socket)
    }
}

/// Runs `operation`, cancelling it and throwing `URLError(.timedOut)` after `timeout`.
func withRelayTimeout<T: Sendable>(
    _ timeout: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw URLError(.timedOut)
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw CancellationError() }
        return result
    }
}
