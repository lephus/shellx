import Foundation
import CmuxControlSocket

/// The two terminal-lifecycle verbs another Mac's Devices sidebar needs that
/// the mobile plane did not have: close one terminal surface, and rename (or
/// clear the custom name of) one terminal surface. Both resolve the target
/// exactly as `mobile.terminal.input` does, so an attach ticket's terminal
/// scope applies unchanged, and both mutate through the same code paths the
/// local socket verbs use (`surface.close`, `surface.action rename`).
extension TerminalController {
    /// `mobile.terminal.close {workspace_id?, surface_id}`: end the terminal
    /// (its process and pane) on this Mac. Refuses the workspace's last
    /// surface, matching the local socket contract.
    func v2MobileTerminalClose(params: [String: Any]) -> V2CallResult {
        if let error = mobileWorkspaceIDValidationError(params: params) {
            return error
        }
        if let error = mobileTerminalAliasValidationError(params: params) {
            return error
        }
        guard let resolved = mobileCanonicalTerminalTarget(params: params) else {
            return .err(code: "not_found", message: String(localized: "devices.host.surfaceNotFound", defaultValue: "Terminal surface not found"), data: nil)
        }
        let workspace = resolved.workspace
        let surfaceID = resolved.surfaceID
        var resolution: ControlSurfaceCloseResolution = .closeFailed(surfaceID)
        v2MainSync {
            resolution = controlSurfaceClose(
                routing: ControlRoutingSelectors(
                    hasWindowIDParam: false, windowID: nil, groupID: nil,
                    workspaceID: workspace.id, surfaceID: surfaceID, paneID: nil
                ),
                surfaceID: surfaceID,
                hasSurfaceIDParam: true
            )
        }
        if case .lastSurface = resolution {
            return .err(code: "invalid_state", message: String(localized: "devices.host.lastSurface", defaultValue: "Cannot close the last surface"), data: nil)
        }
        guard case .closed = resolution else {
            return .err(code: "internal_error", message: String(localized: "devices.host.closeFailed", defaultValue: "Failed to close surface"), data: [
                "surface_id": surfaceID.uuidString,
            ])
        }
        return .ok([
            "workspace_id": workspace.id.uuidString,
            "surface_id": surfaceID.uuidString,
            "closed": true,
        ])
    }

    /// ShellX: closes the terminal tab a live agent runs in, for a phone's `agent.close` (ShellX Link). The caller
    /// has checked that the agent is live and that this workspace lists that terminal. It never asks: the phone
    /// has asked its user. On the workspace's last tab it closes the workspace when the Mac's Close Tab would
    /// (``TabManager/closeWorkspaceOnLastSurfacePreferenceEnabled()``), through ``v2MobileWorkspaceClose(params:)``
    /// and its rules (never a pinned workspace or a window's last one), and is `protected` when that preference
    /// keeps the workspace open. Like the other mobile paths it neither selects a workspace nor brings a window
    /// forward.
    func v2MobileAgentSurfaceClose(workspaceID: UUID, surfaceID: UUID) -> V2CallResult {
        let routing = ControlRoutingSelectors(
            hasWindowIDParam: false, windowID: nil, groupID: nil,
            workspaceID: workspaceID, surfaceID: surfaceID, paneID: nil
        )
        let notFound: V2CallResult = .err(
            code: "not_found",
            message: String(localized: "devices.host.surfaceNotFound", defaultValue: "Terminal surface not found"),
            data: nil
        )
        let lastSurface: V2CallResult = .err(
            code: "protected",
            message: String(localized: "devices.host.lastSurface", defaultValue: "Cannot close the last surface"),
            data: nil
        )
        guard let tabManager = resolveTabManager(routing: routing),
              let workspace = tabManager.tabs.first(where: { $0.id == workspaceID }) else {
            return notFound
        }
        if workspace.panels[surfaceID] != nil, workspace.panels.count <= 1 {
            guard tabManager.closeWorkspaceOnLastSurfacePreferenceEnabled() else { return lastSurface }
            return v2MobileWorkspaceClose(params: ["workspace_id": workspaceID.uuidString, "force": true])
        }
        switch controlSurfaceClose(routing: routing, surfaceID: surfaceID, hasSurfaceIDParam: true, force: true) {
        case .closed:
            return .ok([
                "workspace_id": workspaceID.uuidString,
                "surface_id": surfaceID.uuidString,
                "closed": true,
            ])
        case .surfaceNotFound, .workspaceNotFound, .invalidSurfaceID:
            return notFound
        case .lastSurface:
            // The check above handles the last tab; never close a workspace on this path.
            return lastSurface
        case .denied(_, let message):
            return .err(code: "protected", message: message, data: nil)
        default:
            return .err(
                code: "internal_error",
                message: String(localized: "devices.host.closeFailed", defaultValue: "Failed to close surface"),
                data: nil
            )
        }
    }

    /// `mobile.terminal.rename {workspace_id?, surface_id, title}`: set the
    /// terminal's custom title; an empty title clears it so the shell's own
    /// title shows again.
    func v2MobileTerminalRename(params: [String: Any]) -> V2CallResult {
        guard let rawTitle = params["title"] as? String else {
            return .err(code: "invalid_params", message: String(localized: "devices.host.invalidTitle", defaultValue: "Missing or invalid title"), data: nil)
        }
        if let error = mobileWorkspaceIDValidationError(params: params) {
            return error
        }
        if let error = mobileTerminalAliasValidationError(params: params) {
            return error
        }
        guard let resolved = mobileCanonicalTerminalTarget(params: params) else {
            return .err(code: "not_found", message: String(localized: "devices.host.surfaceNotFound", defaultValue: "Terminal surface not found"), data: nil)
        }
        let workspace = resolved.workspace
        let surfaceID = resolved.surfaceID
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        v2MainSync {
            let panelID = workspace.controlTabTarget(for: surfaceID)?.panelID ?? surfaceID
            _ = workspace.setPanelCustomTitle(panelId: panelID, title: title.isEmpty ? nil : title)
        }
        return .ok([
            "workspace_id": workspace.id.uuidString,
            "surface_id": surfaceID.uuidString,
            "title": v2OrNull(title.isEmpty ? nil : title),
        ])
    }
}
