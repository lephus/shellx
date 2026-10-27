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
    }
}
