import Foundation

public enum LinkEvent: Equatable, Sendable {
    case start, connected(localSocket: String), exited(status: Int32), mintFailed(code: String)
    case machineOffline(lastSeen: Date?), machineOnline, retryDue, stop
}

public enum LinkAction: Equatable, Sendable {
    case mintTicket, spawn, kill, scheduleRetry(at: Date), publish(LinkState)
}

/// Pure transition table for one viewer link. The driver mints a fresh ticket before every spawn.
public struct LinkStateMachine: Sendable {
    public private(set) var state: LinkState = .idle
    private var attempt = 0
    private static let fatalMintCodes: Set<String> = ["unauthorized", "forbidden", "not_logged_in"]

    public init() {}

    public mutating func handle(_ event: LinkEvent, now: Date) -> [LinkAction] {
        switch event {
        case .start:
            switch state {
            case .idle, .failed: return begin()
            default: return []
            }
        case .machineOnline:
            if case .offline = state { return begin() }
            return []
        case .retryDue:
            if case .reconnecting = state { return [.mintTicket, .spawn] }
            return []
        case .connected(let socket):
            switch state {
            case .connecting, .reconnecting, .connected:
                attempt = 0
                state = .connected(localSocket: socket)
                return [.publish(state)]
            default: return []
            }
        case .exited:
            switch state {
            case .connecting, .connected, .reconnecting: return scheduleRetry(now: now)
            default: return []
            }
        case .mintFailed(let code):
            switch state {
            case .connecting, .reconnecting:
                if Self.fatalMintCodes.contains(code) {
                    state = .failed(code: code)
                    return [.publish(state)]
                }
                return scheduleRetry(now: now)
            default: return []
            }
        case .machineOffline(let lastSeen):
            if case .idle = state { return [] }
            state = .offline(lastSeen: lastSeen)
            return [.kill, .publish(state)]
        case .stop:
            if case .idle = state { return [] }
            attempt = 0
            state = .idle
            return [.kill, .publish(.idle)]
        }
    }

    private mutating func begin() -> [LinkAction] {
        attempt = 0
        state = .connecting
        return [.publish(.connecting), .mintTicket, .spawn]
    }

    private mutating func scheduleRetry(now: Date) -> [LinkAction] {
        attempt += 1
        let at = now.addingTimeInterval(ReconnectBackoff.delay(attempt: attempt - 1))
        state = .reconnecting(attempt: attempt, retryAt: at)
        return [.publish(state), .scheduleRetry(at: at)]
    }
}
