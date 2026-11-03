import Bonsplit
import CmuxWorkspaces
import Foundation

extension Workspace {
    /// The Automations tab in this workspace, if one is open.
    var shellXAutomationsPanel: ShellXAutomationsPanel? {
        panels.values.lazy.compactMap { $0 as? ShellXAutomationsPanel }.first
    }

    /// Opens an Automations tab in `paneId`.
    @discardableResult
    func newShellXAutomationsSurface(
        inPane paneId: PaneID,
        controller: ShellXAutomationsController,
        focus: Bool = true
    ) -> ShellXAutomationsPanel? {
        let panel = ShellXAutomationsPanel(controller: controller)
        panels[panel.id] = panel
        panelTitles[panel.id] = panel.displayTitle

        guard let tabId = bonsplitController.createTab(
            title: panel.displayTitle,
            icon: panel.displayIcon,
            kind: SurfaceKind.automations.rawValue,
            isDirty: false,
            isLoading: false,
            isPinned: false,
            inPane: paneId
        ) else {
            panels.removeValue(forKey: panel.id)
            panelTitles.removeValue(forKey: panel.id)
            controller.shutDown()
            return nil
        }

        bindSurface(tabId, toPanelId: panel.id)
        publishCmuxSurfaceCreated(
            panel.id,
            paneId: paneId,
            kind: SurfaceKind.automations.rawValue,
            origin: "shellx_automations",
            focused: focus
        )
        if focus {
            bonsplitController.focusPane(paneId)
            bonsplitController.selectTab(tabId)
            applyTabSelection(tabId: tabId, inPane: paneId)
        }
        return panel
    }
}
