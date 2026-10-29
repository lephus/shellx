import Foundation

/// What a push from a paired Mac says (`userInfo["shellx"]`, relay `POST /v2/notifications`).
public enum PushPayload: Equatable, Sendable {
    /// An agent waits for the user on `machineID`; tapping the alert opens the waiting requests.
    case needsYou(machineID: String, requestID: String)
    /// The request was handled: its alert, if still shown, goes away.
    case resolved(machineID: String, requestID: String)

    /// Nil for a push that is not one of ShellX's, or not one this app version knows.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let shellx = userInfo["shellx"] as? [String: Any],
              let machineID = shellx["machine_id"] as? String, let requestID = shellx["request_id"] as? String
        else { return nil }
        switch shellx["kind"] as? String {
        case "needs_you": self = .needsYou(machineID: machineID, requestID: requestID)
        case "resolved": self = .resolved(machineID: machineID, requestID: requestID)
        default: return nil
        }
    }

    public var requestID: String {
        switch self {
        case let .needsYou(_, id), let .resolved(_, id): id
        }
    }
}
