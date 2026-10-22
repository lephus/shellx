import Foundation

/// This Mac's ShellX Link host: serves the agent Feed to paired phones on the machine's link slot.
///
/// The app implements it, because the Feed lives in the app target. ``ShellXRemoteService`` starts it
/// after `machines.register` returns a `link_slot`, and stops it whenever the host session ends
/// (sign-out, a 401, termination). An old relay returns no `link_slot`; the service then never starts it.
@MainActor
public protocol RemoteLinkHosting: AnyObject, Sendable {
    /// Starts serving the link lane of `machineID` on `linkSlot`, replacing any running host. Returns at once.
    ///
    /// - Parameters:
    ///   - machineID: This machine's id from `machines.register`, the target of self-connect tickets.
    ///   - linkSlot: The relay slot of this machine's ShellX Link lane.
    func start(machineID: String, linkSlot: String)
    /// Stops serving. Returns at once and is idempotent.
    func stop()
}
