import Foundation

/// A change to a pane's agent activity, read from one raw Claude Code hook payload.
///
/// The app reads hook events as they arrive and keeps the ones that matter as
/// signals, which ``AgentActivityMarkerTable`` applies to the pane that sent
/// them. Only Claude Code reports skills and workflows, so the initializer reads
/// Claude's hook subcommands:
///
/// | Subcommand | Signal |
/// |---|---|
/// | `prompt-submit` | ``turnStarted(slashCommandName:)`` |
/// | `pre-tool-use` for the `Skill` tool | ``skillInvoked(name:)`` |
/// | `pre-tool-use` for the `Workflow` tool | ``workflowLaunched(name:)`` |
/// | `stop`, `stop-failure` | ``turnEnded(hasBackgroundWork:)`` |
/// | `session-end` | ``sessionEnded`` |
///
/// ```swift
/// let signal = AgentActivityHookSignal(
///     claudeSubcommand: "pre-tool-use",
///     payload: #"{"tool_name":"Skill","tool_input":{"skill":"brainstorming"}}"#
/// )
/// // signal == .skillInvoked(name: "brainstorming")
/// ```
public enum AgentActivityHookSignal: Sendable, Equatable {
    /// The user submitted a prompt, so a new turn started.
    ///
    /// - Parameter slashCommandName: The name of the `/command` the prompt runs,
    ///   without the slash, or `nil` for an ordinary prompt.
    case turnStarted(slashCommandName: String?)

    /// The agent invoked a skill through the `Skill` tool.
    ///
    /// - Parameter name: The skill name, or `nil` when the payload carried none.
    case skillInvoked(name: String?)

    /// The agent launched a workflow through the `Workflow` tool.
    ///
    /// - Parameter name: The workflow name, or `nil` when the payload carried none.
    case workflowLaunched(name: String?)

    /// The agent's turn ended, whether it finished or stopped on a failure.
    ///
    /// - Parameter hasBackgroundWork: Whether a background task is still running.
    ///   Scheduled crons do not count: one would keep the work looking alive forever.
    case turnEnded(hasBackgroundWork: Bool)

    /// The agent's session ended.
    case sessionEnded

    /// Reads the signal a Claude Code hook event carries, if it carries one.
    ///
    /// Returns `nil` for any other subcommand, for a payload that is not a JSON
    /// object, and for a tool other than `Skill` and `Workflow`. `session-end`
    /// ignores its payload. `stop` also carries Claude's StopFailure event.
    ///
    /// A `Workflow` call is named by its `name` input, or else by the `name` in the
    /// `meta` literal that opens its `script`; with neither it stays unnamed.
    ///
    /// - Parameters:
    ///   - claudeSubcommand: The Claude hook subcommand the event came in under, such as `pre-tool-use`.
    ///   - payload: The raw JSON the hook received, exactly as Claude Code sent it.
    public init?(claudeSubcommand: String, payload: String) {
        switch claudeSubcommand {
        case "prompt-submit":
            guard let object = Self.jsonObject(in: payload) else { return nil }
            self = .turnStarted(slashCommandName: Self.slashCommandName(in: object["prompt"] as? String))
        case "pre-tool-use":
            // Every tool call passes through here, so skip the JSON parse unless the
            // payload can name one of the two tools.
            guard payload.contains("Skill") || payload.contains("Workflow"),
                  let object = Self.jsonObject(in: payload),
                  let toolName = object["tool_name"] as? String else { return nil }
            let toolInput = object["tool_input"] as? [String: Any]
            switch toolName {
            case "Skill":
                self = .skillInvoked(name: Self.trimmedNonEmpty(toolInput?["skill"] as? String))
            case "Workflow":
                self = .workflowLaunched(name: Self.workflowName(in: toolInput))
            default:
                return nil
            }
        case "stop", "stop-failure":
            guard let object = Self.jsonObject(in: payload) else { return nil }
            self = .turnEnded(hasBackgroundWork: Self.hasRunningBackgroundTask(in: object))
        case "session-end":
            self = .sessionEnded
        default:
            return nil
        }
    }
}

// MARK: - Reading hook payloads

extension AgentActivityHookSignal {
    /// A prompt that opens with a slash command, such as `/commit -m fix`.
    private static let slashCommandPattern = try! NSRegularExpression(
        pattern: #"^\s*/([A-Za-z0-9][A-Za-z0-9_.:-]*)"#
    )

    /// The tag Claude Code writes around a slash command it expanded into the prompt.
    private static let commandNameTagPattern = try! NSRegularExpression(
        pattern: #"<command-name>/?([^<\s]+)</command-name>"#
    )

    /// The start of the `meta` literal that opens a workflow script.
    private static let metaOpeningPattern = try! NSRegularExpression(
        pattern: #"\bmeta\s*=\s*\{"#
    )

    /// The `name` entry of a `meta` literal, with a quoted string value.
    private static let nameEntryPattern = try! NSRegularExpression(
        pattern: #"\bname\s*:\s*['"]([^'"]+)['"]"#
    )

    /// The payload as a JSON object, or `nil` when it is anything else.
    private static func jsonObject(in payload: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
    }

    /// The command a prompt runs: a leading `/name`, else a `<command-name>` tag.
    private static func slashCommandName(in prompt: String?) -> String? {
        guard let prompt else { return nil }
        if let name = firstCapture(of: slashCommandPattern, in: prompt) { return name }
        // Scanning the whole prompt is only worth it when it can hold the tag.
        guard prompt.contains("<command-name>") else { return nil }
        return firstCapture(of: commandNameTagPattern, in: prompt)
    }

    /// The workflow's `name` input, else the name in its script's `meta` literal.
    private static func workflowName(in toolInput: [String: Any]?) -> String? {
        if let name = trimmedNonEmpty(toolInput?["name"] as? String) { return name }
        guard let script = toolInput?["script"] as? String,
              let meta = metaLiteral(in: script) else { return nil }
        return trimmedNonEmpty(firstCapture(of: nameEntryPattern, in: String(meta)))
    }

    /// The text between the braces of the `meta = { ... }` literal in a workflow script.
    ///
    /// Searching only this text keeps a `name:` elsewhere in the script, such as in
    /// an error message or another object, from naming the workflow. Braces inside
    /// string literals and comments do not count, and neither do quotes inside
    /// comments. Returns `nil` when the script has no `meta` literal. A literal
    /// whose braces never balance runs to the end of the script, so a name written
    /// before the damage is still found.
    private static func metaLiteral(in script: String) -> Substring? {
        let wholeScript = NSRange(script.startIndex..., in: script)
        guard let opening = metaOpeningPattern.firstMatch(in: script, options: [], range: wholeScript),
              let openingRange = Range(opening.range, in: script) else { return nil }
        var depth = 1
        var quote: Character?
        var isEscaped = false
        var index = openingRange.upperBound
        while index < script.endIndex {
            let character = script[index]
            var next = script.index(after: index)
            if let delimiter = quote {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == delimiter {
                    quote = nil
                }
            } else {
                switch character {
                case "'", "\"", "`":
                    quote = character
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return script[openingRange.upperBound..<index] }
                case "/" where script[next...].hasPrefix("/"):
                    next = script[next...].firstIndex(where: \.isNewline) ?? script.endIndex
                case "/" where script[next...].hasPrefix("*"):
                    next = script[script.index(after: next)...].range(of: "*/")?.upperBound ?? script.endIndex
                default:
                    break
                }
            }
            index = next
        }
        return script[openingRange.upperBound...]
    }

    /// Whether a `Stop` payload lists a background task that is still running.
    ///
    /// Mirrors `hasActiveClaudeBackgroundWork` in the CLI, except that
    /// `session_crons` do not count: a cron never finishes, so it would keep a
    /// workflow marker alive indefinitely. Payloads from older Claude Code
    /// versions carry no `background_tasks` and read as no background work.
    private static func hasRunningBackgroundTask(in object: [String: Any]) -> Bool {
        guard let tasks = object["background_tasks"] as? [[String: Any]] else { return false }
        return tasks.contains { ($0["status"] as? String) == "running" }
    }

    /// The first capture group of the pattern's first match in the text.
    private static func firstCapture(of pattern: NSRegularExpression, in text: String) -> String? {
        let wholeText = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, options: [], range: wholeText),
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    /// The text without surrounding whitespace, or `nil` when nothing is left.
    private static func trimmedNonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
