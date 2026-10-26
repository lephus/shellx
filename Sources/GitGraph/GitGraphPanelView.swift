import SwiftUI

/// Shows a Git Graph page and tells its controller's tracker whether the page is on
/// screen: the tracker watches the repository only then, and refreshes the page
/// once each time it shows again.
struct GitGraphPanelView: View {
    let controller: GitGraphController
    let isVisible: Bool

    var body: some View {
        GitGraphWebView(controller: controller)
            .onAppear { controller.tracker.setVisible(isVisible) }
            .onDisappear { controller.tracker.setVisible(false) }
            .onChange(of: isVisible) { _, visible in
                controller.tracker.setVisible(visible)
            }
    }
}
