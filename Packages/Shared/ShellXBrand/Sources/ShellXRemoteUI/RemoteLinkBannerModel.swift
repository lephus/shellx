import Foundation
import ShellXRemoteCore

/// Localized text for the remote link banner, injected so this module needs
/// no bundle. `reconnecting` and `offline` take the machine's name as their
/// one `%@`; `failed` takes the name and then the error code as `%@`, `%@`;
/// `retryIn` takes the whole seconds as `%lld`.
public struct RemoteLinkBannerLabels: Equatable, Sendable {
    public let reconnecting: String
    public let offline: String
    public let failed: String
    public let retryIn: String

    public init(reconnecting: String, offline: String, failed: String, retryIn: String) {
        self.reconnecting = reconnecting
        self.offline = offline
        self.failed = failed
        self.retryIn = retryIn
    }

    public static let english = RemoteLinkBannerLabels(
        reconnecting: "Reconnecting to %@…",
        offline: "%@ is offline. The session resumes when ShellX opens there.",
        failed: "Can't connect to %@ (%@)",
        retryIn: "retry in %llds"
    )
}

/// What the banner above a remote workspace shows for its machine's link.
/// The banner is one fixed-height line that pushes the terminal pane down:
/// it never covers the terminal and never takes input.
public struct RemoteLinkBannerModel: Equatable, Sendable {
    /// The palette token the text uses: `muted` or `error`.
    public enum Tone: Equatable, Sendable { case muted, error }

    /// Banner height in points. The view uses this constant, so no state or
    /// text length can change it.
    public static let height: Double = 28
    /// The bottom border (palette `line`) in points.
    public static let borderWidth: Double = 1
    /// The countdown never shows more than a day.
    public static let maxCountdownSeconds: Int64 = 86_400
    /// At most this many one-second refreshes are scheduled, counted back
    /// from the retry moment. A snapshot change rebuilds the schedule anyway.
    public static let maxRefreshes = 600

    /// nil: no banner (`idle`, `connected`).
    public let text: String?
    public let tone: Tone
    public let showsSpinner: Bool
    /// The view shows the text on one line with tail truncation.
    public let lineLimit = 1
    /// When the text changes next, for a view that redraws once per second
    /// while a countdown shows. Each date is a whole number of seconds
    /// before `retryAt`, so the text steps down exactly on the second.
    /// Empty without a countdown, and once the countdown has reached 0.
    public let refreshDates: [Date]

    public init(machine: RemoteMachine, now: Date, labels: RemoteLinkBannerLabels = .english) {
        let name = Self.displayName(of: machine)
        switch machine.link {
        case .idle, .connected:
            text = nil
            tone = .muted
            showsSpinner = false
            refreshDates = []
        case .connecting:
            text = String(format: labels.reconnecting, name)
            tone = .muted
            showsSpinner = true
            refreshDates = []
        case .reconnecting(_, let retryAt):
            var line = String(format: labels.reconnecting, name)
            var dates: [Date] = []
            let remaining = retryAt.timeIntervalSince(now)
            if remaining.isFinite {
                let seconds = Self.wholeSeconds(remaining)
                line += " \u{00B7} " + String(format: labels.retryIn, seconds)
                if remaining > 0 {
                    let count = min(Int(min(seconds, Int64(Self.maxRefreshes))), Self.maxRefreshes)
                    dates = (0..<count).reversed().map { retryAt.addingTimeInterval(-Double($0)) }
                }
            }
            text = line
            tone = .muted
            showsSpinner = true
            refreshDates = dates
        case .offline:
            text = String(format: labels.offline, name)
            tone = .muted
            showsSpinner = false
            refreshDates = []
        case .failed(let code):
            text = String(format: labels.failed, name, code)
            tone = .error
            showsSpinner = false
            refreshDates = []
        }
    }

    /// The machine a remote workspace is attached to, or nil when the
    /// workspace is local, the snapshot is missing, or it names a machine the
    /// snapshot does not list (no banner then).
    public static func machine(forWorkspace workspaceID: UUID, in snapshot: RemoteUISnapshot?) -> RemoteMachine? {
        guard let snapshot, let machineID = snapshot.remoteMachineID(forWorkspace: workspaceID) else { return nil }
        return snapshot.machines.first { $0.id == machineID }
    }

    /// `max(0, ceil(remaining))`, capped at `maxCountdownSeconds`.
    private static func wholeSeconds(_ remaining: TimeInterval) -> Int64 {
        guard remaining > 0 else { return 0 }
        guard remaining < Double(maxCountdownSeconds) else { return maxCountdownSeconds }
        return Int64(remaining.rounded(.up))
    }

    /// The machine's name; a blank name falls back to its id.
    private static func displayName(of machine: RemoteMachine) -> String {
        machine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? machine.id : machine.name
    }
}
