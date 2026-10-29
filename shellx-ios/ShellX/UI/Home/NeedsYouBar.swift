import ShellXAppCore
import SwiftUI

/// "Needs you · N" over a conversation: one line with the newest request's headline. A tap opens the
/// "Needs You" page, where the cards are; nothing is decided from here, so the conversation keeps
/// its room. The owner shows it only while something is pending.
struct NeedsYouBar: View {
    let items: [MachinePendingItem]
    /// Two or more Macs are paired: the headline names the Mac.
    let showsMachineName: Bool
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var newest: MachinePendingItem? { items.max { $0.item.createdAtMs < $1.item.createdAtMs } }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        let large = typeSize.isAccessibilitySize
        let layout = large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        Button(action: open) {
            HStack(spacing: 8) {
                layout {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StatusDot(color: Color("StatusNeedsYou"))
                        Text(LocalizedStringResource("pending.section.title \(items.count)"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color("AccentText"))
                            .contentTransition(.numericText(value: Double(items.count)))
                    }
                    .fixedSize()
                    if let newest {
                        Text(Self.headline(for: newest, showsMachineName: showsMachineName))
                            .font(.subheadline)
                            .lineLimit(large ? 2 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color("AccentText"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color("AccentColor").opacity(0.12), in: shape)
            .overlay { shape.strokeBorder(Color("AccentColor").opacity(0.35), lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: items.count)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityHint(Text(LocalizedStringResource("home.needsYou.hint")))
        .accessibilityIdentifier("home.needsYou")
    }

    /// "web · wants to run Bash": the card's headline without the agent, so what is asked fits on
    /// the one line (VoiceOver still hears the agent).
    static func headline(for item: MachinePendingItem, showsMachineName: Bool) -> AttributedString {
        var workspace = AttributedString(item.item.workspaceTitle)
        workspace.font = .subheadline.weight(.semibold)
        let parts = (showsMachineName ? [item.machineName] : []) + [PendingCardView.kindText(item.item)]
        var rest = AttributedString(" · " + parts.joined(separator: " · "))
        rest.foregroundColor = Color.secondary
        return workspace + rest
    }

    /// "Needs you · 3, web, Claude Code, wants to run Bash".
    private var spokenLabel: String {
        let title = String(localized: "pending.section.title \(items.count)")
        guard let newest else { return title }
        return title + ", " + PendingCardView.spokenHeadline(for: newest, showsMachineName: showsMachineName)
    }
}
