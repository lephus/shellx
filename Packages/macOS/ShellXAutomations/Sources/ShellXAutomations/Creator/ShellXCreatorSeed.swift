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
        let jsonFence = fence(around: json)
        let markdownFence = fence(around: skillMarkdown)
        return """
        Edit this existing \(automation.kind.rawValue) named \(automation.name).

        automation.json:
        \(jsonFence)json
        \(json)
        \(jsonFence)

        SKILL.md:
        \(markdownFence)markdown
        \(skillMarkdown)
        \(markdownFence)
        """
    }

    /// A backtick fence longer than any backtick run in `content`, so the content cannot close it.
    private func fence(around content: String) -> String {
        var longest = 0
        var current = 0
        for character in content {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return String(repeating: "`", count: max(3, longest + 1))
    }
}
