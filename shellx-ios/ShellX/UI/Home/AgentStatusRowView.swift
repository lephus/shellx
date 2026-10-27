import ShellXAppCore
import SwiftUI

/// One live session in the agent strip: the state dot, the workspace, "Claude Code · MacBook Pro",
/// and the state in words ("Running for 4 minutes", "Needs you", "Done").
struct AgentStatusRowView: View {
    let row: AgentStatusRow

    @Environment(\.dynamicTypeSize) private var typeSize

    private var style: AgentStateStyle { AgentStateStyle(row) }
    private var place: String { "\(AgentLabel(agent: row.ref.agent).text) · \(row.machineName)" }

    var body: some View {
        let large = typeSize.isAccessibilitySize
        let layout = large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StatusDot(color: style.color ?? .clear)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.ref.workspaceTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(large ? nil : 1)
                    Text(verbatim: place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(large ? nil : 1)
                }
            }
            if !large { Spacer(minLength: 8) }
            if let text = style.text {
                Text(verbatim: text)
                    .font(.subheadline)
                    .foregroundStyle(row.online && row.state == .needsInput ? Color("AccentText") : .secondary)
                    .multilineTextAlignment(large ? .leading : .trailing)
                    .padding(.leading, large ? 18 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [row.ref.workspaceTitle, place, style.text].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityIdentifier("home.agentRow")
    }
}
