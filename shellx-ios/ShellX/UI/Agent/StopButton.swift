import ShellXAppCore
import SwiftUI

/// "Stop" in the agent screen's toolbar: a tap interrupts the agent's current turn (`hard: false`);
/// its menu (touch and hold, or the VoiceOver action) has "Force Stop…", which asks to confirm
/// first (HIG: Pull-down buttons, a destructive item is confirmed in an action sheet). The owner
/// shows it only while the session works or waits for the user.
struct StopButton: View {
    let stop: () -> Void
    /// Asks to confirm Force Stop; the owner presents the confirmation.
    let forceStop: () -> Void

    var body: some View {
        Menu {
            Button(role: .destructive, action: forceStop) {
                Label(String(localized: "agent.forceStop.menu"), systemImage: "xmark.octagon")
            }
        } label: {
            // The word, not only a symbol: a toolbar drops a label's title.
            Text(LocalizedStringResource("agent.stop"))
                .fontWeight(.semibold)
        } primaryAction: {
            stop()
        }
        .tint(Color("StatusError"))
        .accessibilityAction(named: Text(LocalizedStringResource("agent.forceStop.menu")), forceStop)
        .accessibilityIdentifier("agent.stop")
    }

    /// What the screen says after a Stop or Force Stop: the Mac's answer, or why there was none.
    static func text(for outcome: ChatInterruptOutcome?, offline: Bool, machineName: String) -> String {
        switch outcome {
        case .sent:
            return String(localized: "agent.stop.sent")
        case .notFound:
            return String(localized: "agent.gone")
        case .failed, .other:
            return String(localized: "agent.stop.failed")
        case nil:
            return offline
                ? String(localized: "home.note.offline \(machineName)")
                : String(localized: "agent.stop.noAnswer")
        }
    }
}
