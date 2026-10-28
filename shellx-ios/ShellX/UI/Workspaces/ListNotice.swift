import Observation
import SwiftUI

/// A short line the workspace list says once, left there by a screen that went away on its own: the
/// workspace screen, popped because its workspace was closed on the Mac. The list shows it for
/// `AgentView.noticeDuration` (`WorkspaceListView`), then it is cleared.
@MainActor @Observable
final class ListNotice {
    private(set) var current: AgentScreen.Notice?

    func show(_ text: String) {
        current = AgentScreen.Notice(text: text)
    }

    /// Clears the notice `id`; a newer one stays.
    func clear(_ id: UUID) {
        if current?.id == id { current = nil }
    }
}

/// The notice as the list and the agent screen show it: a capsule over the bottom edge.
struct NoticeCapsule: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .transition(.opacity)
            .accessibilityIdentifier("workspaces.notice")
    }
}
