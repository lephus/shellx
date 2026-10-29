import ShellXAppCore
import SwiftUI

/// The default Mac's name and a status dot, at the top left of the home; opens "Your Macs".
struct MacStatusPill: View {
    let name: String
    let state: MachineLinkState
    let open: () -> Void

    private var style: MachineStateStyle { MachineStateStyle(state, machineName: name) }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                StatusDot(color: style.color)
                Text(verbatim: name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 180, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: "\(name), \(style.text)"))
        .accessibilityHint(Text(LocalizedStringResource("home.macPill.hint")))
        .accessibilityIdentifier("home.macPill")
    }
}
