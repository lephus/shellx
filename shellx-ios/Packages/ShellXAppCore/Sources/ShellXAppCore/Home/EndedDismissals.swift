import Foundation
import Observation
import ShellXLinkCore

/// The ended sessions the user took off the phone's Ended list, each with the end time it had then.
/// It only hides a session on this phone, exactly as the 12 hours do (`HomeFocus.endedFor`); nothing is
/// sent to the Mac.
///
/// A dismissal is per Mac, session id and end time: a session that ended again later has a newer end
/// time and shows again, and one that is no longer `.ended` is not on the list whatever this holds.
/// `pruned(now:)` drops what the 12 hours would have dropped anyway.
public struct EndedDismissals: Equatable, Sendable, Codable {
    public static let none = EndedDismissals()

    /// The end time (`HomeFocus.endedMs(of:)`) each dismissed session had, by Mac and session id.
    private var ends: [String: [String: Int64]] = [:]

    public init() {}

    /// True when the user dismissed this session and it has not ended again since.
    public func hides(_ session: MachineSession) -> Bool {
        guard let endedMs = HomeFocus.endedMs(of: session.session),
            let dismissed = ends[session.machineID]?[session.session.sessionId]
        else { return false }
        return endedMs <= dismissed
    }

    /// Takes the session off the list. A session with no end time was never on it, so nothing is kept.
    public mutating func dismiss(_ session: MachineSession) {
        guard let endedMs = HomeFocus.endedMs(of: session.session) else { return }
        let id = session.session.sessionId
        let newest = max(endedMs, ends[session.machineID]?[id] ?? .min)
        ends[session.machineID, default: [:]][id] = newest
    }

    /// Without the sessions whose end is `HomeFocus.endedFor` or more ago: they are off the list anyway.
    public func pruned(now: Date) -> EndedDismissals {
        var kept = EndedDismissals()
        for (machineID, sessions) in ends {
            let fresh = sessions.filter { HomeFocus.endedAge(ms: $0.value, now: now) < HomeFocus.endedFor }
            if !fresh.isEmpty { kept.ends[machineID] = fresh }
        }
        return kept
    }
}

/// Keeps `EndedDismissals` in `UserDefaults` under `shellx.dismissedEnded`, so a dismissal outlives a
/// relaunch for as long as the 12 hours would have kept the session. Old entries go at each launch and
/// each dismissal. Data it cannot read counts as no dismissals.
@MainActor @Observable
public final class EndedDismissalStore {
    static let key = "shellx.dismissedEnded"

    public private(set) var dismissals: EndedDismissals

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(defaults: UserDefaults, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(EndedDismissals.self, from: $0) }
        dismissals = (saved ?? .none).pruned(now: now())
        if dismissals != saved { save() }
    }

    /// The user took the session off the Ended list.
    public func dismiss(_ session: MachineSession) {
        var next = dismissals
        next.dismiss(session)
        dismissals = next.pruned(now: now())
        save()
    }

    private func save() {
        if dismissals == .none {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(dismissals) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
