import SwiftUI

/// A request's text on its card: at most three lines, with "Show more" when there is more than
/// fits. A tool's input is monospaced, a plan keeps its inline Markdown (bold, code).
///
/// A preview may be 8 KB of anything (emoji, right-to-left text): only its first
/// `collapsedCharacters` are laid out, more than three lines can ever show.
struct CommandPreview: View {
    enum Style {
        /// A tool's input: monospaced.
        case command
        /// Questions: the body font.
        case prose
        /// A plan's summary: inline Markdown.
        case markdown
    }

    static let lineLimit = 3
    static let collapsedCharacters = 600

    let text: String
    var style = Style.command
    let showMore: () -> Void

    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var font: Font {
        style == .command ? .system(.footnote, design: .monospaced) : .subheadline
    }

    var body: some View {
        let (shown, cut) = Self.collapsed(text)
        VStack(alignment: .leading, spacing: 2) {
            content(shown)
                .lineLimit(Self.lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { limitedHeight = $0 }
                // The same text without the limit, invisible, tells whether the limit cut it.
                .background(alignment: .topLeading) {
                    content(shown)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if cut || fullHeight > limitedHeight + 1 {
                Button(action: showMore) {
                    Text(LocalizedStringResource("pending.showMore"))
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .tint(Color("AccentText"))
                .accessibilityIdentifier("pending.showMore")
            }
        }
    }

    private func content(_ shown: String) -> Text {
        switch style {
        case .markdown: return Text(PlanMarkdownText.inline(shown)).font(font)
        case .command, .prose: return Text(verbatim: shown).font(font)
        }
    }

    /// The first `collapsedCharacters` characters of `text`, and whether that left some out.
    static func collapsed(_ text: String) -> (text: String, cut: Bool) {
        guard let end = text.index(text.startIndex, offsetBy: collapsedCharacters, limitedBy: text.endIndex),
            end < text.endIndex
        else { return (text, false) }
        return (String(text[..<end]), true)
    }
}
