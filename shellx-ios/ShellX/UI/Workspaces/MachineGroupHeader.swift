import ShellXAppCore
import SwiftUI

/// The top of a Mac's group in the workspace list: a status dot, the Mac's name in small capitals, why
/// it has no rows when it has none ("offline · last seen 08:12"), and how many workspaces it lists.
/// A tap opens "Your Macs".
struct MachineGroupHeader: View {
    let group: WorkspaceGroup
    /// Two or more Macs are paired: the default one says so.
    let showsDefault: Bool
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var style: MachineStateStyle { MachineStateStyle(group.state, machineName: group.name) }
    private var caption: String? { Self.caption(for: group.state, machineName: group.name) }
    private var count: Int? { group.showsRows && group.listsWorkspaces ? group.rows.count : nil }

    /// "08:12", in the app's language.
    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app))
    }

    /// Why a Mac has no rows to show, or how its link stands while it has some; nil when it is simply
    /// online. An offline Mac says when it was last reachable.
    static func caption(for state: MachineLinkState, machineName: String) -> String? {
        switch state {
        case .online:
            return nil
        case let .offline(since):
            return String(localized: "workspaces.group.offline \(time(since))")
        case .connecting, .reconnecting, .revoked, .hostKeyChanged, .needsUpdate:
            return MachineStateStyle(state, machineName: machineName).text
        }
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatusDot(color: style.color)
                Text(verbatim: line)
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(group.showsRows ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityHint(Text(LocalizedStringResource("workspaces.group.hint")))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("workspace.group.\(group.id)")
    }

    /// "MacBook Pro · Default", "Mac mini · offline · last seen 08:12".
    private var line: String {
        var parts = [group.name]
        if showsDefault, group.isDefault { parts.append(String(localized: "machines.default")) }
        if let caption { parts.append(caption) }
        return parts.joined(separator: " · ")
    }

    private var spokenLabel: String {
        var parts = [group.name, style.text]
        if showsDefault, group.isDefault { parts.append(String(localized: "machines.default")) }
        if let count { parts.append(String(localized: "workspaces.group.count \(count)")) }
        return parts.joined(separator: ", ")
    }
}
