import Foundation
import Observation
import ShellXLinkCore

/// One workspace's screen: the workspace as its Mac lists it, the chip shown, and when the screen
/// should give up (the workspace is gone, or never came).
///
/// - The chip shown starts as `defaultTerminal(in:pending:sessions:)` says and changes when the user
///   swipes (`select(_:)`), or when the chip shown leaves the Mac's list: the next chip shows. The sessions
///   and the requests can arrive after the list: until the user picks a chip, a chip that does not show an
///   agent's chat gives way, once, to the pane waiting for the user. What the Mac selects later does not
///   move it.
/// - `phase` is `.dismissed` only for a workspace the screen has seen and that then left the list of a Mac
///   that is online and lists its workspaces (`absence(of:)`): only that Mac says the workspace was closed.
///   A list emptied for another reason (the Mac is offline or no longer reachable from this iPhone, or its
///   list could not be read) keeps the last chips; a Mac removed from this iPhone is `.machineRemoved`. A
///   workspace the Mac has not listed yet (a create's answer can come before the push that lists the new
///   workspace) is `.waiting`; after `patience` the model asks the Mac for its list once more, and when the
///   workspace is still absent the phase is `.notFound` (it still shows if a push lists it later).
/// - A Mac that goes offline leaves the last known list in place, so the chips stay.
///
/// `run()` follows the hub while the screen is shown.
@MainActor @Observable
public final class WorkspaceScreenModel {
    /// How long a workspace the Mac has not listed is waited for before the Mac is asked again.
    public static let patience: Duration = .seconds(5)

    public enum Phase: Equatable, Sendable {
        /// The Mac's list does not have the workspace yet.
        case waiting
        case showing
        /// The workspace was listed, and left: it was closed (on the Mac, or by this screen).
        case dismissed
        /// The workspace's Mac was removed from this iPhone: the screen leaves without a word.
        case machineRemoved
        /// The workspace did not come within `patience`, even after asking the Mac again.
        case notFound
    }

    public let ref: WorkspaceRef
    public private(set) var phase: Phase = .waiting
    /// The terminal id of the chip shown; nil while the workspace has no terminal.
    public private(set) var selectedTerminalId: String?
    /// How many times the chip shown left the Mac's list while the workspace stayed (it was closed on the
    /// Mac): the screen moved to the next chip, and says so in a short line (spec section 6.2).
    public private(set) var shownPaneClosed = 0

    @ObservationIgnored private let hub: MachineHub
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// The workspace was in the Mac's list at some point.
    @ObservationIgnored private var seen = false
    /// The terminal ids as `reconcile()` last saw them, in chip order.
    @ObservationIgnored private var knownTerminalIds: [String] = []
    /// The workspace as the Mac last listed it: shown while the list does not have it for a reason other than
    /// a close (`absence(of:)`).
    @ObservationIgnored private var kept: LinkWorkspace?
    /// The chip shown was chosen for good: the user picked it, the screen moved to the pane waiting for the
    /// user, or the chip shown left and the next one took its place. Until then the screen may still move to
    /// the pane waiting for the user.
    @ObservationIgnored private var settled = false

    /// `sleep` waits out `patience`; tests pass one they release by hand.
    public init(
        ref: WorkspaceRef, hub: MachineHub,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.ref = ref
        self.hub = hub
        self.sleep = sleep
        // The first frame already shows the workspace and its chip, when the list has it.
        reconcile()
    }

    // MARK: - What the screen reads

    private var machine: MachineModel? { hub.machines.first { $0.id == ref.machineID } }

    /// The workspace in the Mac's list as the hub has it now.
    private var listed: LinkWorkspace? { machine?.workspaces.workspace(ref.workspaceId) }

    /// The workspace as its Mac last listed it (also while the Mac is offline, or after the hub emptied the
    /// list of a Mac that did not close it), or nil while the screen has not seen it.
    public var workspace: LinkWorkspace? { listed ?? kept }

    /// The workspace's chips, in the Mac's order. Empty while there is no workspace.
    public var panes: [WorkspacePane] {
        guard let machine, let workspace else { return [] }
        return WorkspacePane.panes(of: workspace) { sessionId in
            machine.sessions.session(sessionId).map {
                MachineSession(
                    machineID: machine.id, machineName: machine.name, online: machine.state == .online, session: $0)
            }
        }
    }

    /// Rename and close reach the Mac: it is online and takes workspace commands.
    public var canControl: Bool {
        machine?.state == .online && hub.supportsWorkspaceControl(ref.machineID)
    }

    // MARK: - Choosing a chip

    /// The chip to show first, as its terminal id:
    /// - an agent whose session needs input waits for the user: among those, one whose agent is the agent of
    ///   a request of the workspace, then the one the Mac has selected, then the first;
    /// - while a request of the workspace waits for the user and no session says it needs input yet, the
    ///   agent the Mac has selected, else the first chip that runs an agent;
    /// - otherwise the chip the Mac has selected;
    /// - otherwise the first chip.
    ///
    /// `pending` are the requests of the workspace's Mac (those of another workspace are ignored).
    /// `sessions` are the sessions the hub lists for that Mac: a terminal naming any other is not an agent
    /// (nil takes every `sessionId` as a live session, in no known state).
    public static func defaultTerminal(
        in workspace: LinkWorkspace, pending: [MachinePendingItem], sessions: [AgentSession]? = nil
    ) -> String? {
        defaultChoice(in: workspace, pending: pending, sessions: sessions).terminalId
    }

    /// `defaultTerminal(in:pending:sessions:)`, and whether that chip is there because it waits for the user.
    static func defaultChoice(
        in workspace: LinkWorkspace, pending: [MachinePendingItem], sessions: [AgentSession]?
    ) -> (terminalId: String?, waitsForUser: Bool) {
        let terminals = WorkspacePane.ordered(workspace.terminals)
        let live = sessions.map { list in
            Dictionary(list.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        }
        func session(of terminal: LinkTerminal) -> AgentSession? {
            terminal.sessionId.flatMap { live?[$0] }
        }
        let agents = terminals.filter { terminal in
            guard let sessionId = terminal.sessionId else { return false }
            return live.map { $0[sessionId] != nil } ?? true
        }
        func preferred(_ chips: [LinkTerminal]) -> String? {
            (chips.first(where: \.selected) ?? chips.first)?.terminalId
        }
        let asking = pending.filter { $0.item.workspaceId == workspace.workspaceId }
        let waiting = agents.filter { session(of: $0)?.state == .needsInput }
        if !waiting.isEmpty {
            let askingAgents = Set(asking.map(\.item.agent))
            let matching = waiting.filter { session(of: $0).map { askingAgents.contains($0.agent) } ?? false }
            return (preferred(matching.isEmpty ? waiting : matching), true)
        }
        if !asking.isEmpty, let agent = preferred(agents) { return (agent, true) }
        return (preferred(terminals), false)
    }

    /// Shows the chip `terminalId` (the user swiped to it). An id the workspace does not have is ignored.
    public func select(_ terminalId: String) {
        // The pager may write back the chip it already shows: only a change is the user's pick.
        guard terminalId != selectedTerminalId,
            workspace?.terminals.contains(where: { $0.terminalId == terminalId }) == true
        else { return }
        selectedTerminalId = terminalId
        settled = true
    }

    /// The chip that takes the place of `gone`: the next one that is still there, else the one before.
    /// `before` are the chips' ids as they were, `now` as they are.
    static func successor(of gone: String, before: [String], now: [String]) -> String? {
        guard let index = before.firstIndex(of: gone) else { return now.first }
        if let after = before[(index + 1)...].first(where: now.contains) { return after }
        if let earlier = before[..<index].last(where: now.contains) { return earlier }
        return now.first
    }

    // MARK: - Following the hub

    /// Follows the hub until cancelled: takes each change of the Mac's workspace list into `phase` and
    /// the chip shown, and gives up waiting for a workspace the Mac does not list (`patience`).
    /// Opening the screen counts as looking at the workspace (`MachineHub.markSeen(_:)`).
    public func run() async {
        hub.markSeen(ref)
        reconcile()
        async let waiting: Void = giveUpWaiting()
        while !Task.isCancelled {
            await nextChange()
            reconcile()
        }
        await waiting
    }

    /// Why the Mac's list, as the hub has it, lacks a workspace the screen saw.
    enum Absence: Equatable {
        /// The Mac is online and lists its workspaces: it closed the workspace.
        case closed
        /// The Mac is no longer paired with this iPhone.
        case machineRemoved
        /// The hub emptied the list without the Mac saying anything (it is offline, no longer reachable from
        /// this iPhone, or its list could not be read): the last chips stay.
        case unknown
    }

    static func absence(of machine: MachineModel?) -> Absence {
        guard let machine else { return .machineRemoved }
        return machine.state == .online && machine.workspacesSupported ? .closed : .unknown
    }

    /// Brings `phase` and the chip shown up to date with the hub's list.
    func reconcile() {
        guard phase != .dismissed, phase != .machineRemoved else { return }
        guard let workspace = listed else {
            // Never listed: still on its way (or `.notFound`).
            guard seen else { return }
            switch Self.absence(of: machine) {
            case .closed: phase = .dismissed
            case .machineRemoved: phase = .machineRemoved
            case .unknown: break
            }
            return
        }
        seen = true
        if kept != workspace { kept = workspace }
        if phase != .showing { phase = .showing }
        let ids = WorkspacePane.ordered(workspace.terminals).map(\.terminalId)
        if let selected = selectedTerminalId, !ids.contains(selected) {
            selectedTerminalId = Self.successor(of: selected, before: knownTerminalIds, now: ids)
            settled = true
            shownPaneClosed += 1
        } else if selectedTerminalId == nil {
            let choice = Self.defaultChoice(in: workspace, pending: pendingHere, sessions: sessionsHere)
            selectedTerminalId = choice.terminalId
            settled = choice.waitsForUser
        } else if !settled, !showsAgent(in: workspace) {
            // The sessions or the request came after the list: move to the pane waiting for the user. A chip
            // that shows an agent's chat stays, so a message being typed is never pulled away.
            let choice = Self.defaultChoice(in: workspace, pending: pendingHere, sessions: sessionsHere)
            if choice.waitsForUser {
                if choice.terminalId != selectedTerminalId { selectedTerminalId = choice.terminalId }
                settled = true
            }
        }
        knownTerminalIds = ids
    }

    private var pendingHere: [MachinePendingItem] {
        hub.pendingItems.filter { $0.isIn(machineID: ref.machineID, workspaceId: ref.workspaceId) }
    }

    private var sessionsHere: [AgentSession] {
        machine?.sessions.sessions ?? []
    }

    /// The chip shown runs an agent the hub lists: its page is that agent's chat.
    private func showsAgent(in workspace: LinkWorkspace) -> Bool {
        guard let selectedTerminalId,
            let sessionId = workspace.terminals.first(where: { $0.terminalId == selectedTerminalId })?.sessionId
        else { return false }
        return machine?.sessions.session(sessionId) != nil
    }

    /// A workspace not listed yet: after `patience` asks the Mac for its list, once; then it either
    /// shows or is not found.
    private func giveUpWaiting() async {
        guard phase == .waiting else { return }
        do { try await sleep(Self.patience) } catch { return }
        guard phase == .waiting else { return }
        await hub.refreshWorkspaces(machineID: ref.machineID)
        reconcile()
        if phase == .waiting { phase = .notFound }
    }

    /// Returns when the workspace the screen looks at (or the Mac it is on) changed in the hub, or, while
    /// the chip shown is not settled, the Mac's sessions or requests; or when the task is cancelled.
    private func nextChange() async {
        let wake = Wake()
        await withTaskCancellationHandler {
            withObservationTracking {
                _ = workspace
                // A Mac back online (or reachable again) says whether a workspace missing from its list was closed.
                _ = machine?.state
                _ = machine?.workspacesSupported
                // Until the chip is settled, the sessions and the requests can still move it.
                if !settled {
                    _ = sessionsHere
                    _ = pendingHere
                }
            } onChange: {
                wake.wake()
            }
            await wake.wait()
        } onCancel: {
            wake.wake()
        }
    }
}

/// Lets a task wait until `wake()` is called, whichever comes first, the wait or the call.
private final class Wake: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var woken = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = lock.withLock { () -> Bool in
                if woken { return true }
                self.continuation = continuation
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func wake() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            woken = true
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume()
    }
}
