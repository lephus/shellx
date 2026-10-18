/// Agent commands that cmux can intercept with a per-surface launch shim.
public enum TerminalSurfaceAgentCommand: String, CaseIterable, Hashable, Sendable {
    case claude
    case codex
    case pi
    case amp
    case hermes
    case agy
}

/// Describes one agent command intercepted by the shared per-surface shim path.
struct TerminalSurfaceAgentCommandShimDefinition: Sendable {
    let command: TerminalSurfaceAgentCommand
    let wrapperName: String
    let environmentVariablePrefix: String

    var commandName: String { command.rawValue }

    /// The single capability table for cmux-managed agent launch wrappers.
    static let bundled: [Self] = [
        Self(
            command: .claude,
            wrapperName: "shellx-claude-wrapper",
            environmentVariablePrefix: "CMUX_CLAUDE"
        ),
        Self(
            command: .codex,
            wrapperName: "shellx-codex-wrapper",
            environmentVariablePrefix: "CMUX_CODEX"
        ),
        Self(
            command: .pi,
            wrapperName: "shellx-pi-wrapper",
            environmentVariablePrefix: "CMUX_PI"
        ),
        Self(
            command: .amp,
            wrapperName: "shellx-amp-wrapper",
            environmentVariablePrefix: "CMUX_AMP"
        ),
        Self(
            command: .hermes,
            wrapperName: "shellx-hermes-agent-wrapper",
            environmentVariablePrefix: "CMUX_HERMES_AGENT"
        ),
        Self(
            command: .agy,
            wrapperName: "agy",
            environmentVariablePrefix: "CMUX_AGY"
        ),
    ]
}
