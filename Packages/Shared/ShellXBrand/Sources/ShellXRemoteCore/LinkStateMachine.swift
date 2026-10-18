import Foundation

public enum LinkEvent: Equatable, Sendable {
    case start, connected(localSocket: String), exited(status: Int32), mintFailed(code: String)
    case machineOffline(lastSeen: Date?), machineOnline, retryDue, stop
}

/// Which failure codes end a link (`.failed`) and which are retried on the backoff.
/// Codes come from shellx-core (`tickets.rs`, `machines.rs`, `store.rs`, `http.rs`: server codes verbatim,
/// `http_<status>`, `network`, `server`) or from the supervisors (`state_dir_insecure`, `invite_expired`).
public enum LinkFailure {
    /// Will not heal by retrying: sign-in, registration, access or local-state problems.
    public static let fatalCodes: Set<String> = [
        "unauthorized", "forbidden", "not_logged_in", "invalid_credentials", "not_registered", "not_granted",
        "machine_not_found", "invalid_machine", "invalid_params", "bad_request", "not_configured",
        "state_dir_insecure", "state_file_insecure", "invite_expired",
    ]

    public static func isFatal(_ code: String) -> Bool {
        if fatalCodes.contains(code) { return true }
        // Other 4xx answers are fatal too, except timeouts and rate limits.
        return code.hasPrefix("http_4") && code != "http_408" && code != "http_429"
    }

    /// The failure code of a core call; anything that is not a core envelope error is retryable.
    public static func code(for error: any Error) -> String {
        (error as? ShellXCoreError)?.code ?? "core_call_failed"
    }
}

public enum LinkAction: Equatable, Sendable {
    case mintTicket, spawn, kill, scheduleRetry(at: Date), publish(LinkState)
}

/// Pure transition table for one viewer link. The driver mints a fresh ticket before every spawn.
public struct LinkStateMachine: Sendable {
    public private(set) var state: LinkState = .idle
    private var attempt = 0

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
                if LinkFailure.isFatal(code) {
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
