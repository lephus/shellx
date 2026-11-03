import Foundation

/// An existing automation handed to the assistant for editing.
public struct ShellXCreatorSeed: Sendable {
    /// The automation to edit.
    public let automation: ShellXAutomation
    /// Its current `SKILL.md` text.
    public let skillMarkdown: String

    /// Creates a seed.
    public init(automation: ShellXAutomation, skillMarkdown: String) {
        self.automation = automation
        self.skillMarkdown = skillMarkdown
    }

    /// The first user message: what to edit plus both files in fenced blocks.
    public var firstMessage: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let json = (try? encoder.encode(automation)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        Edit this existing \(automation.kind.rawValue) named \(automation.name).

        automation.json:
        ```json
        \(json)
        ```

        SKILL.md:
        ```markdown
        \(skillMarkdown)
        ```
        """
    }
}
