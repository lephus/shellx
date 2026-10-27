import ShellXAppCore
import SwiftUI

/// The "Send to: Claude Code · shellx ▾" chip above the composer. Its menu lists the running
/// sessions by Mac (an offline Mac says so), with "Automatic" first: the session messaged last, or
/// the newest on the default Mac (`HomeModel.effectiveTarget`).
struct TargetPicker: View {
    /// Where the next message goes now.
    let current: SessionRef?
    /// The session the user picked, while it is still listed; nil for automatic.
    let picked: SessionRef?
    /// The live sessions, most recent first.
    let sessions: [MachineSession]
    let choose: (SessionRef?) -> Void

    /// The sessions of one Mac.
    private struct MachineGroup: Identifiable {
        let id: String
        let title: String
        var sessions: [MachineSession]
    }

    private var groups: [MachineGroup] {
        var groups: [MachineGroup] = []
        for session in sessions {
            if let index = groups.firstIndex(where: { $0.id == session.machineID }) {
                groups[index].sessions.append(session)
            } else {
                let title = session.online
                    ? session.machineName : String(localized: "machine.state.offline \(session.machineName)")
                groups.append(MachineGroup(id: session.machineID, title: title, sessions: [session]))
            }
        }
        return groups
    }

    static func label(_ ref: SessionRef) -> String {
        "\(AgentLabel(agent: ref.agent).text) · \(ref.workspaceTitle)"
    }

    var body: some View {
        let destination = current.map(Self.label) ?? String(localized: "composer.target.none")
        let chip = String(localized: "composer.target \(destination)")
        Menu {
            Picker(selection: Binding(get: { picked }, set: { choose($0) })) {
                Text(LocalizedStringResource("composer.target.automatic"))
                    .tag(SessionRef?.none)
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { session in
                            Text(verbatim: Self.label(session.ref)).tag(Optional(session.ref))
                        }
                    }
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: chip)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: chip))
        .accessibilityIdentifier("composer.target")
    }
}
