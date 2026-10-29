import ShellXAppCore
import SwiftUI

/// The live sessions as one row of chips under the "Needs you" bar: the state dot, the workspace and
/// the state in a word or two. A chip opens that session's screen. The row scrolls sideways when the
/// chips do not fit, so it never takes more than one line of the screen.
struct AgentChips: View {
    let rows: [AgentStatusRow]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(rows) { row in
                    NavigationLink(value: row.ref) {
                        AgentChip(row: row)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(LocalizedStringResource("agent.open.hint")))
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .accessibilityIdentifier("home.agents")
    }
}

/// One chip: "● relay  4 minutes". VoiceOver hears the workspace, the agent and Mac, and the state.
struct AgentChip: View {
    let row: AgentStatusRow

    private var style: AgentStateStyle { AgentStateStyle(row) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            StatusDot(color: style.color ?? .clear)
            Text(verbatim: row.ref.workspaceTitle)
                .font(.footnote.weight(.semibold))
            if let short = style.shortText {
                Text(verbatim: short)
                    .font(.footnote)
                    .foregroundStyle(row.online && row.state == .needsInput ? Color("AccentText") : .secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        // The capsule stays small; the touch area is the full 44 points.
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityIdentifier("home.agentChip")
    }

    private var spokenLabel: String {
        let place = "\(AgentLabel(agent: row.ref.agent).text) · \(row.machineName)"
        return [row.ref.workspaceTitle, place, style.text].compactMap { $0 }.joined(separator: ", ")
    }
}
