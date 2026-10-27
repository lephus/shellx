import ShellXAppCore
import SwiftUI

/// How a Mac's link state looks: the dot colour and the words next to it. The words always carry
/// the state, so the colour is never the only cue.
struct MachineStateStyle: Equatable {
    let text: String
    /// An asset catalog colour (darker in light mode, the soft tone in dark mode).
    let colorName: String

    var color: Color { Color(colorName) }

    init(_ state: MachineLinkState, machineName: String) {
        switch state {
        case .online:
            text = String(localized: "machine.state.online")
            colorName = "StatusDone"
        case .connecting, .reconnecting:
            text = String(localized: "machine.state.connecting")
            colorName = "StatusRunning"
        case .offline:
            text = String(localized: "machine.state.offline \(machineName)")
            colorName = "StatusIdle"
        case .revoked:
            text = String(localized: "machine.state.revoked")
            colorName = "StatusError"
        case .hostKeyChanged:
            text = String(localized: "machine.state.hostKeyChanged")
            colorName = "StatusError"
        case .needsUpdate:
            text = String(localized: "machine.state.needsUpdate")
            colorName = "StatusNeedsYou"
        }
    }
}

/// The small status dot in front of a state's words.
struct StatusDot: View {
    let color: Color
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
