import ShellXAppCore
import SwiftUI

/// One paired Mac in "Your Macs": its name, a status dot with the state in words, the "Default"
/// badge, and, when the link stopped for good, the one action that helps (pair again, remove).
struct MachineRow: View {
    let name: String
    let state: MachineLinkState
    let isDefault: Bool
    /// The Mac's key changed: scan its new code.
    let pairAgain: () -> Void
    /// The Mac removed this iPhone: take it off the list.
    let remove: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var style: MachineStateStyle { MachineStateStyle(state, machineName: name) }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            details
            if typeSize.isAccessibilitySize == false { Spacer(minLength: 0) }
            action
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var details: some View {
        // At the accessibility text sizes the badge goes under the name, and the icon steps aside,
        // so the name never breaks inside a word.
        let large = typeSize.isAccessibilitySize
        let nameLayout = large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            if !large {
                Image(systemName: "laptopcomputer")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                nameLayout {
                    Text(verbatim: name)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if isDefault { DefaultBadge() }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    StatusDot(color: style.color)
                    Text(verbatim: style.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityIdentifier("machine.row")
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .hostKeyChanged:
            Button(action: pairAgain) {
                Text(LocalizedStringResource("machines.pairAgain"))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Color("AccentText"))
            .accessibilityIdentifier("machine.pairAgain")
        case .revoked:
            Button(role: .destructive, action: remove) {
                Text(LocalizedStringResource("machines.remove"))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("machine.remove")
        default:
            EmptyView()
        }
    }

    /// "MacBook Pro, Connected, Default" for VoiceOver.
    private var accessibilityText: String {
        var parts = [name, style.text]
        if isDefault { parts.append(String(localized: "machines.default")) }
        return parts.joined(separator: ", ")
    }
}

/// The "Default" capsule next to the default Mac's name.
struct DefaultBadge: View {
    var body: some View {
        Text(LocalizedStringResource("machines.default"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color("AccentText"))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color("AccentText").opacity(0.14), in: Capsule())
            .accessibilityHidden(true)
    }
}
