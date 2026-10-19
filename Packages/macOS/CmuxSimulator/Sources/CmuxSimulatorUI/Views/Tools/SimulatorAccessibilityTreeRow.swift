import CmuxSimulator
import SwiftUI
import ShellXIcons

struct SimulatorAccessibilityTreeRow: View {
    let row: SimulatorAccessibilityPresentationRow
    let isHighlighted: Bool
    let onSelect: (SimulatorAccessibilityNode) -> Void

    var body: some View {
        Button { onSelect(row.node) } label: {
            HStack {
                Text(verbatim: row.node.label ?? row.node.role ?? row.node.id)
                    .lineLimit(1)
                    .padding(.leading, CGFloat(min(row.depth, 8)) * 10)
                Spacer()
                if isHighlighted { ShellXIcon.image("scope") }
            }
        }
        .buttonStyle(.plain)
    }
}
