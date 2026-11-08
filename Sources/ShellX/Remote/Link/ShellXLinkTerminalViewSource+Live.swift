import Foundation

extension ShellXLinkTerminalViewSource.Mac {
    /// The Mac's own terminals, found through the list the phone sees.
    @MainActor
    static func live(workspaces: ShellXLinkWorkspaceSource) -> Self {
        Self(
            listedWorkspace: { workspaces.listedWorkspaceID(holding: $0) },
            // The iroh replay's own preparation: it materializes a never-shown terminal and wakes a hibernated agent.
            prepare: { workspace, terminal in
                let params: [String: Any] = ["workspace_id": workspace.uuidString, "surface_id": terminal.uuidString]
                guard let resolved = TerminalController.shared.mobileResolveWorkspaceAndSurface(
                    params: params, requireTerminal: true
                ), let surfaceID = resolved.surfaceId else { return nil }
                resolved.workspace.controlSocketTerminalInputTarget(for: surfaceID)?.resumeAgentHibernationForRemoteAttach()
                return surfaceID
            },
            terminal: { ShellXLinkTerminalView.Terminal.live(surfaceID: $0) },
            sizing: { ShellXLinkTerminalView.Sizing.live(surfaceID: $0, clientID: $1) },
            isBlocked: { MobileRemoteControlPolicy.isDisabled },
            listChanges: { onChange in
                let watching = Task { @MainActor in
                    for await _ in workspaces.workspaceChanges() {
                        onChange()
                    }
                }
                return { watching.cancel() }
            }
        )
    }
}
