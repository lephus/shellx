import Foundation

extension Array where Element == MachineSession {
    /// The session a new message goes to when the user picked none (plan decision D7):
    /// 1. `lastUsed`, while that session is still running on an online Mac;
    /// 2. the most recently active session on the default Mac;
    /// 3. the most recently active session on any online Mac;
    /// 4. nil.
    ///
    /// Ended sessions and sessions on a Mac that is not online are never a target. The result carries
    /// the live session's labels (a renamed workspace shows its new name).
    public func preferredTarget(lastUsed: SessionRef?, defaultMachineID: String?) -> SessionRef? {
        let usable = filter { $0.online && $0.session.state != .ended }
        if let lastUsed, let live = usable.first(where: { $0.ref == lastUsed }) { return live.ref }
        if let defaultMachineID, let newest = usable.filter({ $0.machineID == defaultMachineID }).newest {
            return newest.ref
        }
        return usable.newest?.ref
    }

    /// The most recently active session; ties (and sessions without activity) go by Mac, then id.
    private var newest: MachineSession? {
        self.min { a, b in
            let (lhs, rhs) = (a.session.lastActivityMs ?? .min, b.session.lastActivityMs ?? .min)
            return lhs != rhs ? lhs > rhs : (a.machineID, a.session.sessionId) < (b.machineID, b.session.sessionId)
        }
    }
}
