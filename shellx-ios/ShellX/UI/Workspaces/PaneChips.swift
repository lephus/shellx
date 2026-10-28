import ShellXAppCore
import SwiftUI

/// The row of chips under the workspace screen's bar: one per terminal of the workspace, in the Mac's
/// order, the one shown highlighted. A chip that runs an agent has a dot in the colour of the agent's
/// state (`AgentStateStyle`). The row scrolls sideways, and keeps the chip shown in view.
struct PaneChips: View {
    let panes: [WorkspacePane]
    /// The terminal id of the chip shown.
    let selected: String?
    /// The time the agents' states are read at.
    var now = Date()
    let select: (String) -> Void

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// What a chip says: the tab's name on the Mac; for a tab with none (a Mac that shrank its list to fit),
    /// the agent's name, or "Terminal".
    static func label(for pane: WorkspacePane) -> String {
        if !pane.title.isEmpty { return pane.title }
        return pane.session.map { AgentLabel(agent: $0.session.agent).text } ?? String(localized: "workspace.chip.shell")
    }

    /// The state of the agent in the pane, as the chip's dot and spoken words; nil for a shell, and for a
    /// state this app does not know.
    static func state(of pane: WorkspacePane, now: Date) -> AgentStateStyle? {
        guard let session = pane.session else { return nil }
        let style = AgentStateStyle(AgentStatusRow(session: session, now: now))
        return style.colorName == nil ? nil : style
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(panes) { pane in chip(pane).id(pane.id) }
                }
                .padding(.horizontal, 12)
            }
            .onChange(of: selected) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear {
                if let selected { proxy.scrollTo(selected, anchor: .center) }
            }
        }
        .accessibilityIdentifier("workspace.chips")
    }

    private func chip(_ pane: WorkspacePane) -> some View {
        let isSelected = pane.id == selected
        let state = Self.state(of: pane, now: now)
        return Button {
            select(pane.id)
        } label: {
            HStack(spacing: 6) {
                if let color = state?.color { StatusDot(color: color) }
                Text(verbatim: Self.label(for: pane))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color("AccentText") : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color("AccentColor").opacity(0.12) : Color.appSurface, in: Self.shape)
            .overlay {
                Self.shape.strokeBorder(
                    isSelected ? Color("AccentColor").opacity(0.45) : Color.primary.opacity(0.1), lineWidth: 1)
            }
            // The row is 44 points tall to touch; the chip itself is smaller.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: Self.label(for: pane)))
        .accessibilityValue(Text(verbatim: state?.text ?? ""))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("workspace.chip.\(pane.id)")
    }
}
