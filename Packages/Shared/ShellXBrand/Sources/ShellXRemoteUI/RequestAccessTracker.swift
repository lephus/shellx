import Foundation
import ShellXRemoteCore

/// Which outgoing pairing one request-access sheet follows, across retries
/// and until it is dismissed. Pure state: the app's sheet model owns the
/// Tasks and calls these in order, so a dismissed sheet can neither start a
/// retry nor open a session after the user walked away.
public struct RequestAccessTracker: Sendable {
    public let machineID: RemoteMachine.ID
    /// The raw code `requestAccess` returned, once known.
    public private(set) var expectedCode: String?
    public private(set) var isRetrying = false
    public private(set) var isStopped = false

    private var superseded: Set<OutgoingPairing.ID> = []
    private var retryingFrom: OutgoingPairing.ID?
    private var autoClosed: Set<OutgoingPairing.ID> = []

    public init(machineID: RemoteMachine.ID, expectedCode: String?) {
        self.machineID = machineID
        self.expectedCode = expectedCode
    }

    /// The pairing to show for `outgoing`. Nothing while a retry is in
    /// flight or after `stop()`.
    public func current(in outgoing: [OutgoingPairing]) -> OutgoingPairing? {
        guard !isStopped, !isRetrying else { return nil }
        return RequestAccessModel.currentPairing(
            in: outgoing,
            for: machineID,
            expectedCode: expectedCode,
            excluding: superseded
        )
    }

    /// The sheet was asked for again (the header showed a code); a nil code
    /// keeps the one being followed.
    public mutating func follow(expectedCode code: String?) {
        guard !isStopped, !isRetrying, let code else { return }
        expectedCode = code
    }

    /// "Try again" on `shown`. True when a new request should be made: only
    /// for a pairing that offers it, never twice at once, never once stopped.
    /// The shown pairing is never shown again.
    public mutating func beginRetry(from shown: RequestAccessModel?) -> Bool {
        guard !isStopped, !isRetrying, let shown, shown.primaryAction == .retry else { return false }
        superseded.insert(shown.pairingID)
        retryingFrom = shown.pairingID
        isRetrying = true
        return true
    }

    /// The new request finished. With its `code`, the sheet follows the new
    /// pairing; with nil (it failed) the old pairing is shown again.
    public mutating func finishRetry(code: String?) {
        guard isRetrying else { return }
        isRetrying = false
        let previous = retryingFrom
        retryingFrom = nil
        guard !isStopped else { return }
        if let code {
            expectedCode = code
        } else if let previous {
            superseded.remove(previous)
        }
    }

    /// True once per approved pairing, and never after `stop()`: the caller
    /// then closes the sheet after `RequestAccessModel.autoCloseDelay`.
    public mutating func takeAutoClose(for pairingID: OutgoingPairing.ID) -> Bool {
        guard !isStopped else { return false }
        return autoClosed.insert(pairingID).inserted
    }

    /// The sheet was dismissed.
    public mutating func stop() {
        isStopped = true
    }
}
