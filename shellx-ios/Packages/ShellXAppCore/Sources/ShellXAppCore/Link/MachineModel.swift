import Foundation
import Observation
import ShellXLinkAccount

/// What the UI shows for one paired Mac. `MachineHub` owns it and is the only writer.
@MainActor @Observable
public final class MachineModel: Identifiable {
    /// The Mac's `machineID`.
    public let id: String
    public internal(set) var machine: PairedMachine
    /// The Mac's name: the paired one, then the relay's when `refreshGrants()` sees it renamed.
    public internal(set) var name: String
    public internal(set) var state: MachineLinkState = .connecting
    public internal(set) var pending = PendingSet()
    /// False while the session is not live and synced: cards show, their buttons do not act.
    public internal(set) var pendingActionable = false
    public internal(set) var sessions = SessionSet()
    /// False when the Mac has no session list (an older ShellX). True until known.
    public internal(set) var sessionsSupported = true
    /// The Mac's workspaces; the last known list while the Mac reconnects.
    public internal(set) var workspaces = WorkspaceSet()
    /// True when the Mac listed the `workspaces` feature when it was last online and answered with its
    /// list. False until then, and for a Mac that lists none (an older ShellX).
    public internal(set) var workspacesSupported = false
    /// What the Mac listed in `welcome.features` when it was last online (empty until then): it
    /// stays while the Mac reconnects, so what depends on it does not flicker.
    public internal(set) var hostFeatures: Set<String> = []

    public init(machine: PairedMachine) {
        id = machine.machineID
        self.machine = machine
        name = machine.name
    }

    /// Takes a new pairing record (same `machineID`) and forgets everything learnt from the old link.
    func replace(with machine: PairedMachine) {
        self.machine = machine
        name = machine.name
        state = .connecting
        pending = PendingSet()
        pendingActionable = false
        sessions = SessionSet()
        sessionsSupported = true
        workspaces = WorkspaceSet()
        workspacesSupported = false
        hostFeatures = []
    }
}
