import Foundation

/// Workspace tab that shows the Automations page.
///
/// Owns one ``ShellXAutomationsController`` and the web view showing it, so the page
/// (and a creator chat in progress) outlives switching tabs. Not restored with the session.
@MainActor
final class ShellXAutomationsPanel: Panel {
    let id = UUID()
    let stableSurfaceIdentity = PanelStableSurfaceIdentity()
    let panelType: PanelType = .automations
    let controller: ShellXAutomationsController
    let webHost: ShellXAutomationsWebHost

    init(controller: ShellXAutomationsController) {
        self.controller = controller
        webHost = ShellXAutomationsWebHost(controller: controller)
    }

    var displayTitle: String {
        String(localized: "automations.panel.title", defaultValue: "Automations")
    }

    var displayIcon: String? { "sparkles" }

    func focus() {}
    func unfocus() {}
    func close() {
        webHost.tearDown()
        controller.shutDown()
    }
    func triggerFlash(reason: WorkspaceAttentionFlashReason) { _ = reason }
}
