import Foundation

extension TabManager {
    /// Captures this window's workspaces as a set: the sidebar multi-selection
    /// when it has two or more, otherwise every workspace. Remote workspaces are
    /// left out, as their folders live on another machine.
    func captureWorkspaceSet(named name: String) -> CmuxWorkspaceSet {
        let localWorkspaces = workspaceSetCandidates
        let workspacesById = Dictionary(uniqueKeysWithValues: localWorkspaces.map { ($0.id, $0) })
        let ids = WorkspaceSetPlan.workspaceIdsToSave(
            orderedIds: localWorkspaces.map(\.id),
            selectedIds: sidebarSelectedWorkspaceIds
        )
        return CmuxWorkspaceSet(
            name: name,
            workspaces: ids.compactMap { workspacesById[$0] }.map { Self.workspaceSetEntry(for: $0) }
        )
    }

    /// Whether ``captureWorkspaceSet(named:)`` saves only the sidebar
    /// multi-selection rather than every workspace in the window.
    var workspaceSetSavesSelection: Bool {
        WorkspaceSetPlan.savesSelection(
            orderedIds: workspaceSetCandidates.map(\.id),
            selectedIds: sidebarSelectedWorkspaceIds
        )
    }

    /// Opens the set's workspaces whose folders are not open in this window yet,
    /// at the end of the sidebar in saved order, then focuses the set's first
    /// workspace. Returns the workspaces it opened.
    @discardableResult
    func openWorkspaceSet(_ workspaceSet: CmuxWorkspaceSet) -> [Workspace] {
        let localWorkspaces = workspaceSetCandidates
        let openIndices = WorkspaceSetPlan.openWorkspaceIndices(
            savedDirectories: workspaceSet.workspaces.map(\.cwd),
            openDirectories: localWorkspaces.map(\.currentDirectory),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let indices = openIndices.indices.filter { openIndices[$0] == nil }
        var openedByIndex: [Int: Workspace] = [:]
        for index in indices {
            let definition = workspaceSet.workspaces[index]
            openedByIndex[index] = openWorkspace(
                fromDefinition: definition,
                title: definition.name,
                cwdOverride: nil,
                focus: false,
                placementOverride: .end
            )
        }

        let firstWorkspace = openedByIndex[0]
            ?? openIndices.first.flatMap { $0 }.map { localWorkspaces[$0] }
        if let firstWorkspace {
            selectWorkspace(firstWorkspace)
        }
        return indices.compactMap { openedByIndex[$0] }
    }

    /// The workspaces a set can hold. Remote workspaces are left out, as their
    /// folders live on another machine.
    private var workspaceSetCandidates: [Workspace] {
        tabs.filter { !$0.isRemoteWorkspace && !$0.isRemoteTmuxMirror }
    }

    private static func workspaceSetEntry(for workspace: Workspace) -> CmuxWorkspaceDefinition {
        var definition = (try? workspace.captureLayoutDefinition().workspace)
            ?? CmuxWorkspaceDefinition(cwd: workspace.currentDirectory, color: workspace.customColor)
        // An automatic title describes the task in progress and goes stale, so
        // a set keeps only the names the user chose.
        definition.name = workspace.effectiveCustomTitleSource == .user
            ? workspace.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        return definition
    }
}
