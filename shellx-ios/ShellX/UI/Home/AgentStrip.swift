import ShellXAppCore
import SwiftUI

/// "Agents · N": one row per live session, under the pinned cards; a row opens that session's
/// screen. It collapses to its title and a dot per session, so the conversation keeps room;
/// VoiceOver hears expanded or collapsed.
struct AgentStrip: View {
    let rows: [AgentStatusRow]
    @Binding var expanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    NavigationLink(value: row.ref) {
                        HStack(spacing: 8) {
                            AgentStatusRowView(row: row)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(LocalizedStringResource("agent.open.hint")))
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text(LocalizedStringResource("home.agents.title \(rows.count)"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !expanded {
                    HStack(spacing: 4) {
                        ForEach(rows.prefix(8)) { row in
                            StatusDot(color: AgentStateStyle(row).color ?? .clear)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .tint(.secondary)
        .accessibilityIdentifier("home.agents")
    }
}
