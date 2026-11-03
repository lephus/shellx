import Foundation

/// Splits the assistant's text into chat text and structured `shellx-draft` / `shellx-choices` blocks.
public struct ShellXAssistantBlockParser: Sendable {
    private static let fence = "```"
    private static let blockPrefix = "shellx-"

    private var pending = ""
    private var inBlock = false

    /// Creates a parser.
    public init() {}

    /// Feeds a streamed text delta and returns the text that is safe to show.
    ///
    /// Text inside a `shellx-` fence, and a fence that may still turn into one, is withheld.
    public mutating func ingest(delta: String) -> String {
        pending += delta
        var visible = ""
        while true {
            if inBlock {
                // A fence line without its newline may still grow (```json), so wait for the newline.
                guard let close = Self.closingFence(in: pending[...]), close.terminated else { return visible }
                pending = String(pending[close.range.upperBound...])
                inBlock = false
                continue
            }
            guard let open = pending.range(of: Self.fence) else {
                let held = Self.trailingBackticks(pending)
                visible += pending.dropLast(held)
                pending = String(pending.suffix(held))
                return visible
            }
            visible += pending[..<open.lowerBound]
            let rest = String(pending[open.upperBound...])
            if let newline = rest.firstIndex(of: "\n") {
                let info = rest[..<newline]
                if info.hasPrefix(Self.blockPrefix) {
                    inBlock = true
                    pending = String(rest[rest.index(after: newline)...])
                } else {
                    visible += Self.fence + rest[...newline]
                    pending = String(rest[rest.index(after: newline)...])
                }
            } else if rest.hasPrefix(Self.blockPrefix) || Self.blockPrefix.hasPrefix(rest) {
                // The info string is not complete yet; it may still become a `shellx-` fence.
                pending = Self.fence + rest
                return visible
            } else {
                visible += Self.fence
                pending = rest
            }
        }
    }

    /// Parses a complete assistant message.
    ///
    /// - Returns: the chat text without structured blocks, the last valid draft and the last valid choices.
    public func finish(fullText: String) -> (visible: String, draft: ShellXAutomationDraft?, choices: ShellXCreatorChoices?) {
        var visible = ""
        var draft: ShellXAutomationDraft?
        var choices: ShellXCreatorChoices?
        var rest = Substring(fullText)
        while let open = rest.range(of: Self.fence) {
            visible += rest[..<open.lowerBound]
            let afterFence = rest[open.upperBound...]
            let infoEnd = afterFence.firstIndex(of: "\n") ?? afterFence.endIndex
            let info = afterFence[..<infoEnd]
            guard info.hasPrefix(Self.blockPrefix) else {
                visible += Self.fence + afterFence[..<infoEnd]
                rest = afterFence[infoEnd...]
                continue
            }
            let bodyStart = infoEnd < afterFence.endIndex ? afterFence.index(after: infoEnd) : infoEnd
            let body = afterFence[bodyStart...]
            let close = Self.closingFence(in: body)?.range
            let json = close.map { body[..<$0.lowerBound] } ?? body
            let data = Data(json.utf8)
            switch info.trimmingCharacters(in: .whitespaces) {
            case "shellx-draft":
                if close != nil, let payload = try? JSONDecoder().decode(ShellXCreatorDraftPayload.self, from: data) {
                    draft = payload.draft
                }
            case "shellx-choices":
                if close != nil, let decoded = try? JSONDecoder().decode(ShellXCreatorChoices.self, from: data) {
                    choices = decoded
                }
            default:
                break
            }
            guard let close else { rest = ""; break }
            rest = body[close.upperBound...]
        }
        visible += rest
        return (visible.trimmingCharacters(in: .whitespacesAndNewlines), draft, choices)
    }

    /// Finds the first line that is only a fence (plus trailing spaces).
    ///
    /// `range` covers the line including its newline; `terminated` tells whether the newline was present.
    /// Valid JSON bodies hold newlines only as `\n` escapes, so a line-start fence is never inside the JSON.
    private static func closingFence(in text: Substring) -> (range: Range<Substring.Index>, terminated: Bool)? {
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let newline = text[lineStart...].firstIndex(of: "\n")
            let lineEnd = newline ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if line.hasPrefix(fence), line.dropFirst(fence.count).allSatisfy({ $0 == " " }) {
                let end = newline.map { text.index(after: $0) } ?? text.endIndex
                return (lineStart..<end, newline != nil)
            }
            guard let newline else { return nil }
            lineStart = text.index(after: newline)
        }
        return nil
    }

    private static func trailingBackticks(_ text: String) -> Int {
        var count = 0
        for ch in text.reversed() {
            guard ch == "`", count < 2 else { break }
            count += 1
        }
        return count
    }
}
