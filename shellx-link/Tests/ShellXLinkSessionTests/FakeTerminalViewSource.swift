import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// A `TerminalCreator` that logs its calls and answers what the test says.
final class FakeTerminalCreator: TerminalCreator, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var result: (outcome: WorkspaceControlOutcome, terminalId: String?) = (.ok, "t-new")
    private var gate: Gate?

    var calls: [String] { lock.withLock { _calls } }

    func setCreate(_ outcome: WorkspaceControlOutcome, terminalId: String?) {
        lock.withLock { result = (outcome, terminalId) }
    }

    /// Later calls wait for `gate` after they are logged.
    func hold(until gate: Gate) {
        lock.withLock { self.gate = gate }
    }

    func createTerminal(workspaceId: String) async -> (outcome: WorkspaceControlOutcome, terminalId: String?) {
        let (answer, gate) = lock.withLock { () -> ((outcome: WorkspaceControlOutcome, terminalId: String?), Gate?) in
            _calls.append(workspaceId)
            return (result, self.gate)
        }
        await gate?.wait()
        return answer
    }
}
