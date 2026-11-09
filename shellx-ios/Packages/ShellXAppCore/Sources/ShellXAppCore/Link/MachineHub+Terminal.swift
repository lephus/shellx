import Foundation
import ShellXLinkCore
import ShellXLinkSession
import os

private let terminalLog = Logger(subsystem: "com.shellx.app", category: "terminal")

/// The terminal view calls (PROTOCOL.md section 11) on each Mac's live session. Nothing is sent to a Mac that is not
/// online or that did not list `terminal_view`.
extension MachineHub: TerminalLink {
    /// Every terminal push of every Mac's live session and every Mac's link state, in the order the hub took them.
    /// Multicast like `chatUpdates()`: a subscriber is dropped when its reader stops, and nothing is kept for a later one.
    public func terminalEvents() -> AsyncStream<TerminalHubEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TerminalHubEvent.self)
        let id = UUID()
        terminalSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.terminalSubscribers[id] = nil }
        }
        return stream
    }

    public func isOnline(_ machineID: String) -> Bool {
        machines.first { $0.id == machineID }?.state == .online
    }

    /// True when the Mac listed the `terminal_view` feature when it was last online.
    public func supportsTerminalView(_ machineID: String) -> Bool {
        machines.first { $0.id == machineID }?.hostFeatures.contains(ShellXLink.terminalViewFeature) ?? false
    }

    public func openTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async -> TerminalOpenResult {
        guard canView(machineID) else { return .notSent }
        do {
            return .outcome(try await withLink(machineID) {
                try await $0.openTerminalView(terminalId: terminalId, cols: cols, rows: rows)
            })
        } catch is LinkCallError {
            return .notSent
        } catch LinkClientError.remote {
            return .outcome(.failed)
        } catch {
            return .noAnswer
        }
    }

    public func closeTerminalView(machineID: String, terminalId: String) async {
        await post(machineID) { try await $0.closeTerminalView(terminalId: terminalId) }
    }

    public func sendTerminalInput(machineID: String, terminalId: String, units: [TerminalInputUnit]) async {
        await post(machineID) { try await $0.sendTerminalInput(terminalId: terminalId, units: units) }
    }

    public func resizeTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async {
        await post(machineID) { try await $0.resizeTerminalView(terminalId: terminalId, cols: cols, rows: rows) }
    }

    public func resyncTerminalView(machineID: String, terminalId: String) async {
        await post(machineID) { try await $0.resyncTerminalView(terminalId: terminalId) }
    }

    public func recordLatency(_ metric: LatencyMetric, _ duration: Duration) {
        latency.record(metric, duration)
    }

    /// Hands a terminal event to every subscriber.
    func publishTerminal(_ event: TerminalHubEvent) {
        for (id, continuation) in terminalSubscribers {
            if case .terminated = continuation.yield(event) { terminalSubscribers[id] = nil }
        }
    }

    private func canView(_ machineID: String) -> Bool {
        isOnline(machineID) && supportsTerminalView(machineID)
    }

    /// Sends one terminal message that expects no answer. Errors are logged (codes only) and dropped.
    private func post(_ machineID: String, _ body: @Sendable (LinkClient) async throws -> Void) async {
        guard canView(machineID) else { return }
        do {
            try await withLink(machineID, body)
        } catch is TerminalInputError {
            terminalLog.info("terminal_input_refused")
        } catch {
            terminalLog.info("terminal_send_failed")
        }
    }
}

extension MachineHub {
    /// True when the Mac listed `terminal_create` when it was last online (the ＋ chip).
    public func supportsTerminalCreate(_ machineID: String) -> Bool {
        machines.first { $0.id == machineID }?.hostFeatures.contains(ShellXLink.terminalCreateFeature) ?? false
    }

    /// Opens a terminal tab in the workspace on its Mac (`terminal.create`); `terminalId` only with `.ok`. Sent once, like the
    /// workspace commands: `.offline` and nothing sent when the Mac is not online, `.failed` without `terminal_create`,
    /// `.unknown` when the answer was lost. The tab joins the workspace list when the Mac's list change arrives.
    public func createTerminal(_ ref: WorkspaceRef) async -> (result: WorkspaceCommandResult, terminalId: String?) {
        let made = CreatedTerminal()
        let result = await workspaceCommand(ref.machineID, feature: ShellXLink.terminalCreateFeature) { client in
            let answer = try await client.createTerminal(workspaceId: ref.workspaceId)
            let result = WorkspaceCommandResult(outcome: answer.outcome)
            if result == .ok(workspaceId: nil) { made.set(answer.terminalId) }
            return result
        }
        return (result, result == .ok(workspaceId: nil) ? made.value : nil)
    }
}

/// The id `createTerminal(_:)` got back, kept out of the `Sendable` command body.
private final class CreatedTerminal: Sendable {
    private let id = OSAllocatedUnfairLock<String?>(initialState: nil)

    func set(_ value: String?) { id.withLock { $0 = value } }
    var value: String? { id.withLock { $0 } }
}
