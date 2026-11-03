import Foundation

/// Holds an Automations link that arrived before the app could show it.
///
/// A banner click that launches ShellX delivers its URL before Automations started and before
/// the previous session was restored. Opening a panel then would be lost, or would make a window
/// the restore does not expect. The link waits here, the newest one winning, until ``flush(isReady:open:)``
/// is called once the app is ready; it is opened exactly once.
@MainActor
final class ShellXAutomationsOpenQueue {
    private var pending: ShellXAutomationsURL?

    /// Whether a link is waiting.
    var hasPending: Bool { pending != nil }

    /// Opens `link` now when the app is ready, else keeps it for ``flush(isReady:open:)``.
    func submit(_ link: ShellXAutomationsURL, isReady: Bool, open: (_ focusId: String?) -> Void) {
        guard isReady else {
            pending = link
            return
        }
        pending = nil
        open(link.focusId)
    }

    /// Opens the waiting link, once, when the app is ready.
    func flush(isReady: Bool, open: (_ focusId: String?) -> Void) {
        guard isReady, let link = pending else { return }
        pending = nil
        open(link.focusId)
    }
}
