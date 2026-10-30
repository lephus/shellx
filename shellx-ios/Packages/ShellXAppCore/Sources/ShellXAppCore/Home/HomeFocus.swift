import Foundation
import ShellXLinkCore

/// One session on the home, with what its row shows beyond the session itself.
public struct FocusItem: Identifiable, Equatable, Sendable {
    public var session: MachineSession
    /// From `SessionName.distinct` over the list the item is in.
    public var name: String
    /// The first line of the matched request (needs-you items only).
    public var question: String?
    /// When the phone saw the session finish (just-finished items only).
    public var finishedAt: Date?

    public init(session: MachineSession, name: String, question: String? = nil, finishedAt: Date? = nil) {
        self.session = session
        self.name = name
        self.question = question
        self.finishedAt = finishedAt
    }

    public var id: SessionRef { session.ref }
}

/// Which group of the home each session goes in: needs you, running, just finished, and the ended fold.
public struct HomeFocus: Equatable, Sendable {
    public var needsYou: [FocusItem]
    public var running: [FocusItem]
    public var justDone: [FocusItem]
    /// Newest end first.
    public var ended: [FocusItem]

    /// How long a finished session stays in "just finished", counted from when the phone saw it finish.
    public static let justDoneFor: TimeInterval = 3600
    /// How long an ended session stays in the Ended fold, counted from its end.
    public static let endedFor: TimeInterval = 43_200

    public static let empty = HomeFocus(needsYou: [], running: [], justDone: [], ended: [])

    /// Nothing needs you, nothing runs and nothing just finished.
    public var isQuiet: Bool { needsYou.isEmpty && running.isEmpty && justDone.isEmpty }

    /// Sorts `sessions`, first match wins per session:
    /// - needs you: every `.needsInput` session; plus, for each request in `pending` that no `.needsInput`
    ///   session of its Mac, workspace and agent matches, the most recently active matching session that is
    ///   not `.ended`. A request matching nothing adds nothing. The question of a card is that of the first
    ///   request in `pending` matching it; a request goes to the most recently active matching card;
    /// - running: `.working`;
    /// - just finished: `.idle` and in `finished` (per Mac, by session id) for less than `justDoneFor`;
    /// - ended: `.ended` for less than `endedFor`, counted from `stateSinceMs`, else `lastActivityMs`
    ///   (`endedMs(of:)`); with neither the session is hidden. A negative age (the Mac's clock is ahead)
    ///   counts as 0. A session in `dismissed` (the user took it off the list) is left out too.
    ///
    /// The first three lists are newest activity first, then by (machineID, sessionId). Names are distinct
    /// across those three together; Ended has its own pass.
    public static func make(
        sessions: [MachineSession], pending: [MachinePendingItem], finished: [String: [String: Date]],
        dismissed: EndedDismissals = .none, now: Date, timeZone: TimeZone = .current
    ) -> HomeFocus {
        var waiting = Set(sessions.filter { $0.session.state == .needsInput }.map(\.ref))
        var questions: [SessionRef: String] = [:]
        for request in pending {
            let matching = sessions.filter {
                $0.machineID == request.machineID && $0.session.workspaceId == request.item.workspaceId
                    && $0.session.agent == request.item.agent
            }
            var target = newest(matching.filter { $0.session.state == .needsInput })
            if target == nil {
                target = newest(matching.filter { $0.session.state != .ended })
                if let target { waiting.insert(target.ref) }
            }
            if let target, questions[target.ref] == nil, let line = request.item.previewText.flatMap(WorkspaceRow.firstLine) {
                questions[target.ref] = line
            }
        }

        var needs: [MachineSession] = []
        var running: [MachineSession] = []
        var done: [MachineSession] = []
        var ended: [(session: MachineSession, endedMs: Int64)] = []
        for machineSession in sessions {
            let session = machineSession.session
            if waiting.contains(machineSession.ref) {
                needs.append(machineSession)
            } else if session.state == .working {
                running.append(machineSession)
            } else if session.state == .idle, let at = finished[machineSession.machineID]?[session.sessionId],
                max(0, now.timeIntervalSince(at)) < justDoneFor
            {
                done.append(machineSession)
            } else if session.state == .ended, let endedMs = endedMs(of: session) {
                if endedAge(ms: endedMs, now: now) < endedFor, !dismissed.hides(machineSession) {
                    ended.append((machineSession, endedMs))
                }
            }
        }

        needs.sort(by: activityFirst)
        running.sort(by: activityFirst)
        done.sort(by: activityFirst)
        ended.sort {
            $0.endedMs != $1.endedMs ? $0.endedMs > $1.endedMs : identityOrder($0.session, $1.session)
        }

        let topNames = SessionName.distinct(needs + running + done, timeZone: timeZone)
        let endedSessions = ended.map(\.session)
        let endedNames = SessionName.distinct(endedSessions, timeZone: timeZone)
        // Only needs-you sessions ever get a question, so the other lists carry none.
        func items(_ list: [MachineSession], _ names: [SessionRef: String]) -> [FocusItem] {
            list.map { FocusItem(session: $0, name: names[$0.ref] ?? "", question: questions[$0.ref]) }
        }
        return HomeFocus(
            needsYou: items(needs, topNames),
            running: items(running, topNames),
            justDone: done.map {
                FocusItem(
                    session: $0, name: topNames[$0.ref] ?? "",
                    finishedAt: finished[$0.machineID]?[$0.session.sessionId])
            },
            ended: items(endedSessions, endedNames))
    }

    /// When the session ended, as the Mac's milliseconds: when it entered its state, else its last activity.
    /// Nil when the Mac gave neither; such a session is never on the Ended list.
    public static func endedMs(of session: AgentSession) -> Int64? {
        session.stateSinceMs ?? session.lastActivityMs
    }

    /// How long ago an end at `ms` was. A negative age (the Mac's clock is ahead) counts as 0.
    static func endedAge(ms: Int64, now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince1970 - Double(ms) / 1000)
    }

    /// The most recently active of `sessions`; ties go to the lower `sessionId`.
    private static func newest(_ sessions: [MachineSession]) -> MachineSession? {
        sessions.min(by: activityFirst)
    }

    private static func activityFirst(_ a: MachineSession, _ b: MachineSession) -> Bool {
        let x = a.session.lastActivityMs ?? .min
        let y = b.session.lastActivityMs ?? .min
        return x != y ? x > y : identityOrder(a, b)
    }

    private static func identityOrder(_ a: MachineSession, _ b: MachineSession) -> Bool {
        (a.machineID, a.session.sessionId) < (b.machineID, b.session.sessionId)
    }
}
