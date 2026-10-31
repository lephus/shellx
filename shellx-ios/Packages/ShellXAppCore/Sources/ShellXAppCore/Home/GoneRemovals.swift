import Foundation
import Observation
import ShellXLinkCore

/// The sessions the user removed from this phone after their Mac answered `not_found` for them ("This
/// session is gone from the Mac", spec 6.8), each with what the Mac reported for it then. It only hides a
/// session on this phone, as the Ended page's trash does (`EndedDismissals`); nothing is sent to the Mac.
///
/// A removal is per Mac and session id, stamped with the session's state, when it entered it and its last
/// activity. The session stays hidden while its Mac reports exactly that stamp; any change shows it again.
/// `shown(_:)` is the one filter every list and count of the phone's sessions goes through (`HomeFocus.make`,
/// the outside-workspace list). `pruned(now:)` drops removals made `keptFor` or more ago, by the phone's clock.
public struct GoneRemovals: Equatable, Sendable, Codable {
    public static let none = GoneRemovals()

    /// How long a removal is kept, counted from when it was made: 30 days.
    public static let keptFor: TimeInterval = 30 * 86_400

    /// What the Mac reported for a session: a removal holds while it reports the same.
    public struct Stamp: Equatable, Sendable, Codable {
        public var state: AgentState
        public var stateSinceMs: Int64?
        public var lastActivityMs: Int64?

        public init(_ session: AgentSession) {
            state = session.state
            stateSinceMs = session.stateSinceMs
            lastActivityMs = session.lastActivityMs
        }
    }

    private struct Removal: Equatable, Sendable, Codable {
        var stamp: Stamp
        /// When the user removed it, by the phone's clock.
        var removedAt: Date
    }

    /// By Mac, then by session id.
    private var removals: [String: [String: Removal]] = [:]

    public init() {}

    /// True when the user removed this session and its Mac reports it exactly as it did then.
    public func hides(_ session: MachineSession) -> Bool {
        removals[session.machineID]?[session.session.sessionId]?.stamp == Stamp(session.session)
    }

    /// `sessions` without the ones this hides, in their order.
    public func shown(_ sessions: [MachineSession]) -> [MachineSession] {
        removals.isEmpty ? sessions : sessions.filter { !hides($0) }
    }

    /// Hides the session as its Mac reports it now; `date` is when, by the phone's clock. A removal of the
    /// same session made before is replaced.
    public mutating func remove(_ session: MachineSession, at date: Date) {
        removals[session.machineID, default: [:]][session.session.sessionId] = Removal(
            stamp: Stamp(session.session), removedAt: date)
    }

    /// Without the removals made `keptFor` or more before `now`. One made after `now` (the phone's clock
    /// went back) is kept.
    public func pruned(now: Date) -> GoneRemovals {
        var kept = GoneRemovals()
        for (machineID, sessions) in removals {
            let fresh = sessions.filter { max(0, now.timeIntervalSince($0.value.removedAt)) < Self.keptFor }
            if !fresh.isEmpty { kept.removals[machineID] = fresh }
        }
        return kept
    }
}

/// Keeps `GoneRemovals` in `UserDefaults` under `shellx.removedGone`, so a removal outlives a relaunch for
/// 30 days. Old entries go at each launch and each removal. Data it cannot read counts as no removals.
///
/// It also knows, for this run only, which sessions an agent screen heard answered `not_found` for
/// (`noteGone(_:)`): only those swipe to "Remove from This Phone" on the home and the outside-workspace
/// list, while their Mac reports them as it did then. The phone cannot tell a ghost from a live session
/// before it asks, and a live session never gets the action.
@MainActor @Observable
public final class GoneRemovalStore {
    static let key = "shellx.removedGone"

    public private(set) var removals: GoneRemovals
    /// The sessions seen gone this run, with what their Mac reported for them then. Never saved.
    private var knownGone: [SessionRef: GoneRemovals.Stamp] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(defaults: UserDefaults, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(GoneRemovals.self, from: $0) }
        removals = (saved ?? .none).pruned(now: now())
        if removals != saved { save() }
    }

    /// An agent screen heard its Mac answer `not_found` for this session, which the Mac still lists
    /// (`AgentThreadModel.ghost`).
    public func noteGone(_ session: MachineSession) {
        let stamp = GoneRemovals.Stamp(session.session)
        if knownGone[session.ref] != stamp { knownGone[session.ref] = stamp }
    }

    /// The session's card swipes to "Remove from This Phone": it was seen gone this run and its Mac reports
    /// it as it did then.
    public func canRemove(_ session: MachineSession) -> Bool {
        knownGone[session.ref] == GoneRemovals.Stamp(session.session)
    }

    /// The ones of `sessions` that `canRemove(_:)`.
    public func removable(_ sessions: [MachineSession]) -> Set<SessionRef> {
        guard !knownGone.isEmpty else { return [] }
        return Set(sessions.filter { canRemove($0) }.map(\.ref))
    }

    /// The user removed the session from this phone (the agent screen, or a card's swipe).
    public func remove(_ session: MachineSession) {
        var next = removals
        next.remove(session, at: now())
        removals = next.pruned(now: now())
        save()
    }

    private func save() {
        if removals == .none {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(removals) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
