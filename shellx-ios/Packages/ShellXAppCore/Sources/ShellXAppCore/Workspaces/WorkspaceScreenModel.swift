import Foundation
import Observation
import ShellXLinkCore

/// One workspace's screen: the workspace as its Mac lists it, the chip shown, and when the screen
/// should give up (the workspace is gone, or never came).
///
/// - The chip shown starts as `defaultTerminal(in:pending:liveSessionIds:)` says and changes only when
///   the user swipes (`select(_:)`), or when the chip shown leaves the Mac's list: the next chip shows.
///   What the Mac selects later does not move it.
/// - `phase` is `.dismissed` only for a workspace the screen has seen and that then left the list. A
///   workspace the Mac has not listed yet (a create's answer can come before the push that lists the
///   new workspace) is `.waiting`; after `patience` the model asks the Mac for its list once more, and
///   when the workspace is still absent the phase is `.notFound` (it still shows if a push lists it later).
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
        /// The workspace did not come within `patience`, even after asking the Mac again.
        case notFound
    }

    public let ref: WorkspaceRef
    public private(set) var phase: Phase = .waiting
    /// The terminal id of the chip shown; nil while the workspace has no terminal.
    public private(set) var selectedTerminalId: String?

    @ObservationIgnored private let hub: MachineHub
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// The workspace was in the Mac's list at some point.
    @ObservationIgnored private var seen = false
    /// The terminal ids as `reconcile()` last saw them, in chip order.
    @ObservationIgnored private var knownTerminalIds: [String] = []

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

    /// The workspace as its Mac last listed it (also while the Mac is offline), or nil while the list
    /// does not have it.
    public var workspace: LinkWorkspace? { machine?.workspaces.workspace(ref.workspaceId) }

    /// The workspace's chips, in the Mac's order. Empty while there is no workspace.
    public var panes: [WorkspacePane] {
        guard let machine, let workspace = machine.workspaces.workspace(ref.workspaceId) else { return [] }
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
    /// - while a request of the workspace waits for the user, the agent that asks: the first chip that
    ///   runs an agent, the one the Mac has selected if that is one (a request does not say which
    ///   agent asks);
    /// - otherwise the chip the Mac has selected;
    /// - otherwise the first chip.
    ///
    /// `pending` are the requests of the workspace's Mac (those of another workspace are ignored).
    /// `liveSessionIds` are the sessions the hub lists: a terminal naming any other is not an agent
    /// (nil takes every `sessionId` as a live session).
    public static func defaultTerminal(
        in workspace: LinkWorkspace, pending: [MachinePendingItem], liveSessionIds: Set<String>? = nil
    ) -> String? {
        let terminals = WorkspacePane.ordered(workspace.terminals)
        func runsAgent(_ terminal: LinkTerminal) -> Bool {
            guard let sessionId = terminal.sessionId else { return false }
            return liveSessionIds?.contains(sessionId) ?? true
        }
        let mine = pending.contains { $0.item.workspaceId == workspace.workspaceId }
        if mine {
            let agents = terminals.filter(runsAgent)
            if let agent = agents.first(where: \.selected) ?? agents.first { return agent.terminalId }
        }
        return (terminals.first(where: \.selected) ?? terminals.first)?.terminalId
    }

    /// Shows the chip `terminalId` (the user swiped to it). An id the workspace does not have is ignored.
    public func select(_ terminalId: String) {
        guard terminalId != selectedTerminalId,
            workspace?.terminals.contains(where: { $0.terminalId == terminalId }) == true
        else { return }
        selectedTerminalId = terminalId
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

    /// Brings `phase` and the chip shown up to date with the hub's list.
    func reconcile() {
        guard phase != .dismissed else { return }
        guard let workspace else {
            // Gone after it was listed: closed. Never listed: still on its way (or `.notFound`).
            if seen { phase = .dismissed }
            return
        }
        seen = true
        if phase != .showing { phase = .showing }
        let ids = WorkspacePane.ordered(workspace.terminals).map(\.terminalId)
        if let selected = selectedTerminalId {
            if !ids.contains(selected) {
                selectedTerminalId = Self.successor(of: selected, before: knownTerminalIds, now: ids)
            }
        } else {
            selectedTerminalId = Self.defaultTerminal(
                in: workspace, pending: pendingHere, liveSessionIds: liveSessionIds)
        }
        knownTerminalIds = ids
    }

    private var pendingHere: [MachinePendingItem] {
        hub.pendingItems.filter { $0.isIn(machineID: ref.machineID, workspaceId: ref.workspaceId) }
    }

    private var liveSessionIds: Set<String> {
        Set(machine?.sessions.sessions.map(\.sessionId) ?? [])
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

    /// Returns when the workspace the screen looks at (or the Mac it is on) changed in the hub, or
    /// when the task is cancelled.
    private func nextChange() async {
        let wake = Wake()
        await withTaskCancellationHandler {
            withObservationTracking {
                _ = workspace
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
