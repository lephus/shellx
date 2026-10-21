import Foundation

public enum ShareSocketMessage: Sendable, Equatable {
    case text(String)
    case data(Data)
}

/// One WebSocket to the relay. `receive` throws once the socket is closed or fails.
public protocol ShareSocket: Sendable {
    func send(text: String) async throws
    func send(data: Data) async throws
    func receive() async throws -> ShareSocketMessage
    func close()
}

public protocol ShareSocketFactory: Sendable {
    func open(_ url: URL) async throws -> any ShareSocket
}

/// Real sockets over `URLSessionWebSocketTask`. No Origin header is set (the relay rejects
/// any Origin it does not allowlist).
public struct URLSessionShareSocketFactory: ShareSocketFactory {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func open(_ url: URL) async throws -> any ShareSocket {
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 1024 * 1024
        task.resume()
        return URLSessionShareSocket(task: task)
    }
}

public final class URLSessionShareSocket: ShareSocket, @unchecked Sendable {
    // URLSessionWebSocketTask is thread-safe; it is only reached through these methods.
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) { self.task = task }

    public func send(text: String) async throws { try await task.send(.string(text)) }
    public func send(data: Data) async throws { try await task.send(.data(data)) }

    public func receive() async throws -> ShareSocketMessage {
        switch try await task.receive() {
        case .string(let s): return .text(s)
        case .data(let d): return .data(d)
        @unknown default: throw URLError(.cannotParseResponse)
        }
    }

    public func close() { task.cancel(with: .normalClosure, reason: nil) }
}

/// Waits until a wall-clock deadline; injectable so tests drive virtual time.
public protocol ShareSleeper: Sendable {
    func sleep(until deadline: Date) async throws
}

public struct ShareSystemSleeper: ShareSleeper {
    private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = Date.init) { self.clock = clock }

    public func sleep(until deadline: Date) async throws {
        let seconds = deadline.timeIntervalSince(clock())
        if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) } else { try Task.checkCancellation() }
    }
}
