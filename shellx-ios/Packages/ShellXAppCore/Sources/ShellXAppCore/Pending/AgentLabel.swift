import Foundation

/// The name shown for an agent: `claude` is "Claude Code", `codex` is "Codex", any other wire name
/// is shown as it is. Product names are never translated.
public struct AgentLabel: Equatable, Sendable {
    public let text: String

    public init(agent: String) {
        switch agent {
        case "claude": text = "Claude Code"
        case "codex": text = "Codex"
        default: text = agent
        }
    }
}
