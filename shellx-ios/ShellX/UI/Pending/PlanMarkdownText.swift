import SwiftUI

/// An agent's plan, drawn from its Markdown: headings, bullet and numbered lists, code blocks,
/// rules and paragraphs, with inline styles (bold, italic, code, links). SwiftUI's `Text` only
/// draws inline Markdown, so the lines are sorted into blocks here first. Selectable for copying.
struct PlanMarkdownText: View {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case bullet(text: String, level: Int)
        case numbered(number: String, text: String, level: Int)
        case code(String)
        case rule
        case paragraph(String)
    }

    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(Self.inline(text))
                .font(level == 1 ? .title3.weight(.semibold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case let .bullet(text, level):
            listRow(marker: "•", text: text, level: level)
        case let .numbered(number, text, level):
            listRow(marker: number + ".", text: text, level: level)
        case let .code(code):
            Text(verbatim: code)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        case let .paragraph(text):
            Text(Self.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func listRow(marker: String, text: String, level: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: marker)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(Self.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(min(level, 4)) * 16)
    }

    /// Inline Markdown of one block, its line breaks kept; the text as it is when it does not parse.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// The plan as plain lines for a card's three-line preview: no blank lines, no heading marks,
    /// list items with their bullet or number; inline Markdown is kept for `inline(_:)`.
    static func summary(_ markdown: String) -> String {
        blocks(markdown).compactMap { block -> String? in
            switch block {
            case let .heading(_, text): return text
            case let .bullet(text, _): return "• " + text
            case let .numbered(number, text, _): return number + ". " + text
            case let .code(code): return code
            case .rule: return nil
            case let .paragraph(text): return text
            }
        }
        .joined(separator: "\n")
    }

    /// Sorts the plan's lines into blocks. Lines in a row form one paragraph; a blank line ends it.
    static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func endParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = code {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    code = open + [line]
                }
                continue
            }
            let level = line.prefix { $0 == " " || $0 == "\t" }.count / 2
            if trimmed.hasPrefix("```") {
                endParagraph()
                code = []
            } else if trimmed.isEmpty {
                endParagraph()
            } else if let heading = heading(trimmed) {
                endParagraph()
                blocks.append(heading)
            } else if ["---", "***", "___"].contains(trimmed) {
                endParagraph()
                blocks.append(.rule)
            } else if let marker = ["- ", "* ", "+ "].first(where: trimmed.hasPrefix) {
                endParagraph()
                blocks.append(.bullet(text: String(trimmed.dropFirst(marker.count)), level: level))
            } else if let (number, text) = numbered(trimmed) {
                endParagraph()
                blocks.append(.numbered(number: number, text: text, level: level))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        endParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)))
    }

    /// "12. Text" or "12) Text".
    private static func numbered(_ line: String) -> (String, String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        return (String(digits), String(rest.dropFirst(2)))
    }
}
