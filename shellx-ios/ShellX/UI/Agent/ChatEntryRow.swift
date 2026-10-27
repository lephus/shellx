import ShellXAppCore
import SwiftUI

/// One entry of an agent's chat, drawn by its kind:
/// - prose: the user's on the right in a bubble, as typed; the agent's on the left from its Markdown
///   (inline styles, lists and code blocks, `PlanMarkdownText`);
/// - thought: collapsed under "Thinking", grey; tapping it shows the text;
/// - tool use: one line, the tool's name and its input in monospace; tapping it shows all of it;
/// - status: centred, small;
/// - anything else: small, grey.
///
/// An entry the Mac cut short ends with "… (cut; see it in full on the Mac)".
struct ChatEntryRow: View {
    let entry: ChatEntry
    /// "Claude Code", for VoiceOver.
    let agent: String

    @State private var expanded: Bool

    init(entry: ChatEntry, agent: String, expanded: Bool = false) {
        self.entry = entry
        self.agent = agent
        _expanded = State(initialValue: expanded)
    }

    private var isMine: Bool { entry.role == .user && entry.kind == .prose }
    private var isCut: Bool { entry.truncated == true }

    var body: some View {
        VStack(alignment: isMine ? .trailing : entry.kind == .status ? .center : .leading, spacing: 4) {
            content
            if isCut {
                Text(LocalizedStringResource("agent.cut"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isMine ? .trailing : .leading)
                    .accessibilityIdentifier("agent.entry.cut")
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : entry.kind == .status ? .center : .leading)
        .padding(isMine ? .leading : .trailing, isMine ? 40 : 0)
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .prose where isMine:
            Text(verbatim: entry.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Color("BubbleMine"),
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 4, topTrailingRadius: 14))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: Self.accessibilityText(for: entry, agent: agent)))
        case .prose:
            PlanMarkdownText(markdown: entry.text)
                .foregroundStyle(entry.role == .agent ? .primary : .secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: Self.accessibilityText(for: entry, agent: agent)))
        case .thought:
            thought
        case .toolUse:
            toolUse
        case .status:
            Text(verbatim: entry.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        case .other:
            Text(verbatim: entry.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var thought: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(verbatim: entry.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            Label {
                Text(LocalizedStringResource("agent.thought"))
            } icon: {
                Image(systemName: "brain")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44, alignment: .leading)
        }
        .tint(.secondary)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("agent.entry.thought")
    }

    private var toolUse: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let tool = entry.toolName, !tool.isEmpty {
                    Text(verbatim: tool)
                        .font(.subheadline.weight(.semibold))
                        .layoutPriority(1)
                }
                Text(verbatim: entry.text)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.accessibilityText(for: entry, agent: agent)))
        .accessibilityHint(expanded ? Text(verbatim: "") : Text(LocalizedStringResource("agent.tool.expandHint")))
        .accessibilityIdentifier("agent.entry.tool")
    }

    /// What VoiceOver reads for the entry: who wrote it, its text, and the cut notice when the Mac cut it.
    static func accessibilityText(for entry: ChatEntry, agent: String) -> String {
        var parts: [String] = []
        switch (entry.role, entry.kind) {
        case (.user, .prose):
            parts.append("\(String(localized: "home.sender.you")): \(entry.text)")
        case (.agent, .prose):
            parts.append("\(agent): \(entry.text)")
        case (_, .toolUse):
            parts.append([entry.toolName, entry.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": "))
        case (_, .thought):
            parts.append("\(String(localized: "agent.thought")): \(entry.text)")
        default:
            parts.append(entry.text)
        }
        if entry.truncated == true { parts.append(String(localized: "agent.cut")) }
        return parts.joined(separator: " ")
    }
}
