import ShellXAppCore
import SwiftUI

/// The "Send to: Claude Code · shellx ▾" chip above the composer. Its menu lists the running
/// sessions by Mac, with "Automatic" first: the session messaged last, or the newest on the default
/// Mac (`HomeModel.effectiveTarget`). An offline Mac's sessions stay listed under "… is offline",
/// but cannot be picked.
struct TargetPicker: View {
    /// Where the next message goes now.
    let current: SessionRef?
    /// The session the user picked, while it is still listed; nil for automatic.
    let picked: SessionRef?
    /// The live sessions, most recent first.
    let sessions: [MachineSession]
    let choose: (SessionRef?) -> Void

    /// The sessions of one Mac, as the menu lists them. A session on an offline Mac cannot take a
    /// message: it is shown, but not `selectable`.
    struct MachineGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let selectable: Bool
        var sessions: [SessionRef]
    }

    /// `sessions` by Mac, in the order of each Mac's first session; an offline Mac's title says so.
    static func groups(_ sessions: [MachineSession]) -> [MachineGroup] {
        var groups: [MachineGroup] = []
        for session in sessions {
            if let index = groups.firstIndex(where: { $0.id == session.machineID }) {
                groups[index].sessions.append(session.ref)
            } else {
                let title = session.online
                    ? session.machineName : String(localized: "machine.state.offline \(session.machineName)")
                groups.append(
                    MachineGroup(id: session.machineID, title: title, selectable: session.online, sessions: [session.ref]))
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
                ForEach(Self.groups(sessions)) { group in
                    Section(group.title) {
                        ForEach(group.sessions, id: \.self) { ref in
                            Text(verbatim: Self.label(ref))
                                .tag(Optional(ref))
                                .disabled(!group.selectable)
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
