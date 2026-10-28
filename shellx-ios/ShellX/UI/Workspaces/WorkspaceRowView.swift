import ShellXAppCore
import SwiftUI

/// One workspace as a card, like a row of the Mac's sidebar: its name and, to the right, a label for
/// its state (none when it is idle); under them in monospace `branch · directory · :ports`; and, while
/// an agent asks, its question. A workspace that waits for the user has the accent colour as its
/// outline. The card is not a button itself: the list wraps it in one.
struct WorkspaceRowView: View {
    let row: WorkspaceRow
    /// The Mac is not online: this is its last known list, so the card fades.
    var dimmed = false

    @Environment(\.dynamicTypeSize) private var typeSize

    private var id: String { row.id.workspaceId }
    private var style: AgentStateStyle { AgentStateStyle(row.state) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    /// `branch · directory · :port :port`, whatever of it the Mac gave; nil when it gave none.
    static func metaLine(for row: WorkspaceRow) -> String? {
        var parts: [String] = []
        if let branch = row.branch, !branch.isEmpty { parts.append(branch) }
        if let directory = row.directory, !directory.isEmpty { parts.append(directory) }
        if !row.ports.isEmpty { parts.append(row.ports.map { ":\($0)" }.joined(separator: " ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What an agent asks, in quotes, while the workspace waits for the user; nil otherwise.
    static func quotedQuestion(for row: WorkspaceRow) -> String? {
        guard row.state == .needsYou, let question = row.question, !question.isEmpty else { return nil }
        return "\u{201C}\(question)\u{201D}"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLine
            if let meta = Self.metaLine(for: row) {
                Text(verbatim: meta)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
            }
            if let question = Self.quotedQuestion(for: row) {
                Text(verbatim: question)
                    .font(.footnote)
                    .foregroundStyle(Color("AccentText"))
                    .lineLimit(2)
                    .padding(.top, 2)
                    .accessibilityIdentifier("workspace.question.\(id)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.appSurface, in: shape)
        .overlay { shape.strokeBorder(border, lineWidth: 1) }
        .contentShape(shape)
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.row.\(id)")
    }

    private var border: Color {
        row.state == .needsYou ? Color("AccentColor").opacity(0.45) : Color.primary.opacity(0.1)
    }

    /// The name and the state label side by side; under each other at the accessibility text sizes,
    /// so neither breaks inside a word.
    private var titleLine: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(verbatim: row.title)
                .font(.headline)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let text = style.text, let color = style.color {
                Text(verbatim: text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .fixedSize()
                    .accessibilityIdentifier("workspace.state.\(id)")
            }
        }
    }
}
