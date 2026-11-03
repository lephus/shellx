import Foundation

/// Workspace tab that shows the Automations page.
///
/// Owns one ``ShellXAutomationsController``; the web view is built by
/// ``ShellXAutomationsPanelView`` and binds to it. Not restored with the session.
@MainActor
final class ShellXAutomationsPanel: Panel {
    let id = UUID()
    let stableSurfaceIdentity = PanelStableSurfaceIdentity()
    let panelType: PanelType = .automations
    let controller: ShellXAutomationsController

    init(controller: ShellXAutomationsController) {
        self.controller = controller
    }

    var displayTitle: String {
        String(localized: "automations.panel.title", defaultValue: "Automations")
    }

    var displayIcon: String? { "sparkles" }

    func focus() {}
    func unfocus() {}
    func close() { controller.shutDown() }
    func triggerFlash(reason: WorkspaceAttentionFlashReason) { _ = reason }
}
