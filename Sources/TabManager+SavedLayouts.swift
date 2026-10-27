import CmuxSettings
import Foundation

extension TabManager {
    @discardableResult
    func openWorkspace(fromSavedLayout layout: CmuxSavedLayout, cwdOverride: String?, focus: Bool) -> Workspace? {
        openWorkspace(
            fromDefinition: layout.workspace,
            title: layout.workspace.name ?? layout.name,
            cwdOverride: cwdOverride,
            focus: focus
        )
    }

    @discardableResult
    func openWorkspace(
        fromDefinition definition: CmuxWorkspaceDefinition,
        title: String?,
        cwdOverride: String?,
        focus: Bool,
        placementOverride: WorkspacePlacement? = nil
    ) -> Workspace? {
        let baseCwd = FileManager.default.homeDirectoryForCurrentUser.path
        let resolvedCwd = CmuxConfigStore.resolveCwd(cwdOverride ?? definition.cwd, relativeTo: baseCwd)
        guard let workspace = addWorkspaceIfActive(
            title: title,
            workingDirectory: resolvedCwd,
            workspaceEnvironment: definition.env ?? [:],
            inheritWorkingDirectory: false,
            select: focus,
            placementOverride: placementOverride
        ) else { return nil }
        if let color = definition.color {
            setTabColor(tabId: workspace.id, color: color)
        }
        if let layoutNode = definition.layout {
            workspace.applyCustomLayout(layoutNode, baseCwd: resolvedCwd)
        }
        return workspace
    }
}
