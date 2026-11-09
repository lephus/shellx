import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// What the hub tells terminal pages, in the order it took it from the Macs.
public enum TerminalHubEvent: Equatable, Sendable {
    /// A push of the Mac's live session (`LinkClient.terminalPushes`).
    case push(machineID: String, TerminalViewPush)
    /// The Mac's link state changed; `.online` comes again after every reconnect, and a view opened before it is gone.
    case state(machineID: String, MachineLinkState)
}

/// How a `terminal.view.open` went.
public enum TerminalOpenResult: Equatable, Sendable {
    case outcome(TerminalViewOpenOutcome)
    /// Nothing was sent: the Mac is not online, or did not list `terminal_view`.
    case notSent
    /// Sent, but no answer came: the session ended or the call timed out.
    case noAnswer
}

/// The hub as a terminal page uses it. `MachineHub` is the real one; tests script one.
@MainActor public protocol TerminalLink: AnyObject {
    /// Every terminal push and link state of every Mac, from now on. Each call adds a subscriber.
    func terminalEvents() -> AsyncStream<TerminalHubEvent>
    func isOnline(_ machineID: String) -> Bool
    /// True when the Mac listed `terminal_view` when it was last online.
    func supportsTerminalView(_ machineID: String) -> Bool
    func openTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async -> TerminalOpenResult
    func closeTerminalView(machineID: String, terminalId: String) async
    func sendTerminalInput(machineID: String, terminalId: String, units: [TerminalInputUnit]) async
    func resizeTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async
    func resyncTerminalView(machineID: String, terminalId: String) async
    func recordLatency(_ metric: LatencyMetric, _ duration: Duration)
}
