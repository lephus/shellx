import Foundation
import ShellXRemoteCore

/// Localized text for the request-access sheet, injected so this module
/// needs no bundle. `title` and `instructions` take the target machine's
/// name as their one `%@`.
public struct RequestAccessLabels: Equatable, Sendable {
    public let title: String
    public let instructions: String
    public let approved: String
    public let denied: String
    public let expired: String
    /// Shown for `.failed(code: "network")`; any other code is shown as is.
    public let network: String

    public init(title: String, instructions: String, approved: String, denied: String, expired: String, network: String) {
        self.title = title
        self.instructions = instructions
        self.approved = approved
        self.denied = denied
        self.expired = expired
        self.network = network
    }

    public static let english = RequestAccessLabels(
        title: "Request access to %@",
        instructions: "On %@, approve only if the code and fingerprint match this screen.",
        approved: "Approved",
        denied: "Denied",
        expired: "Expired",
        network: "Can't reach relay.shellx.pro"
    )
}

/// What the request-access sheet shows for one outgoing pairing. The code
/// and this Mac's own fingerprint are shown in every state: the target
/// machine compares both before it approves.
public struct RequestAccessModel: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case retry }
    /// The palette token the status line uses.
    public enum Tone: Equatable, Sendable { case done, error, muted }

    /// How long an approved sheet stays up before it closes and opens the session.
    public static let autoCloseDelay: TimeInterval = 1

    public let pairingID: OutgoingPairing.ID
    public let title: String
    /// The view shows the title on one line with tail truncation.
    public let titleLineLimit = 1
    /// "123 456"
    public let codeText: String
    /// This Mac's fingerprint, "a1b2 c3d4 e5f6 0718".
    public let fingerprintText: String
    /// Names the target machine; may wrap.
    public let instructions: String
    public let statusText: String?
    public let statusTone: Tone?
    public let showsSpinner: Bool
    public let primaryAction: Action?
    public let closesAutomatically: Bool

    /// The pairing the sheet for `machineID` shows: the newest one to that
    /// machine that was not retried, preferring the code `requestAccess`
    /// returned so an older request never stands in for the new one.
    public static func currentPairing(
        in outgoing: [OutgoingPairing],
        for machineID: RemoteMachine.ID,
        expectedCode: String?,
        excluding superseded: Set<OutgoingPairing.ID>
    ) -> OutgoingPairing? {
        let candidates = outgoing.filter { $0.toMachineID == machineID && !superseded.contains($0.id) }
        func newest(_ list: [OutgoingPairing]) -> OutgoingPairing? {
            list.max { $0.createdAt < $1.createdAt }
        }
        if let expectedCode, let match = newest(candidates.filter({ $0.code == expectedCode })) {
            return match
        }
        return newest(candidates)
    }

    public init(pairing: OutgoingPairing, machineName: String, labels: RequestAccessLabels = .english) {
        pairingID = pairing.id
        title = String(format: labels.title, machineName)
        codeText = PairingDisplay.code(pairing.code)
        fingerprintText = PairingDisplay.fingerprint(pairing.ownFingerprint)
        instructions = String(format: labels.instructions, machineName)
        switch pairing.status {
        case .waiting:
            statusText = nil
            statusTone = nil
            showsSpinner = true
            primaryAction = nil
            closesAutomatically = false
        case .approved:
            statusText = labels.approved
            statusTone = .done
            showsSpinner = false
            primaryAction = nil
            closesAutomatically = true
        case .denied:
            statusText = labels.denied
            statusTone = .error
            showsSpinner = false
            primaryAction = nil
            closesAutomatically = false
        case .expired:
            statusText = labels.expired
            statusTone = .muted
            showsSpinner = false
            primaryAction = .retry
            closesAutomatically = false
        case .failed(let code):
            statusText = code == "network" ? labels.network : code
            statusTone = .error
            showsSpinner = false
            primaryAction = .retry
            closesAutomatically = false
        }
    }
}
