import CmuxSidebar
import Foundation

/// Reads the skill and workflow activity a raw Claude Code hook event reports.
///
/// `agent.hook.enqueue` asks for it on the socket thread, before the event
/// enters the delivery queue: the queue drops best-effort tool events when its
/// tool slots are full, and such a `PreToolUse` may be the only report of a
/// `Skill` or `Workflow` call. Only Claude Code reports skills and workflows, so
/// other agents' events are skipped. ``AgentActivityHookSignal`` does the
/// parsing: it returns at once for subcommands it does not read and scans a
/// tool event's bytes for the two tool names before it parses any JSON.
struct AgentActivityHookObserver {
    /// The workspace, surface and signal a hook event reports.
    ///
    /// - Parameter event: A hook event as `agent.hook.enqueue` built it.
    /// - Returns: The ids from the event's `CMUX_WORKSPACE_ID` and
    ///   `CMUX_SURFACE_ID` with its signal, or `nil` for another agent, an event
    ///   without both ids, or one that carries no signal.
    func observation(
        for event: AgentHookDeliveryEvent
    ) -> (workspaceId: UUID, surfaceId: UUID, signal: AgentActivityHookSignal)? {
        guard event.agent == "claude",
              let workspaceId = Self.uuid(event.environment["CMUX_WORKSPACE_ID"]),
              let surfaceId = Self.uuid(event.environment["CMUX_SURFACE_ID"]),
              let signal = AgentActivityHookSignal(
                  claudeSubcommand: event.subcommand,
                  payload: event.payload
              ) else {
            return nil
        }
        return (workspaceId, surfaceId, signal)
    }

    private static func uuid(_ value: String?) -> UUID? {
        value.flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
