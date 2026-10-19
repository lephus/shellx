import CmuxTerminal
import Foundation
import GhosttyKit
import os
import ShellXRemoteCore

/// ShellX: lets the one-line hook in `cmuxTerminalOutputTeeCallback` call the package tee
/// without an extra import in that upstream file.
typealias ShellXBridgeTee = ShellXRemoteCore.ShellXBridgeTee

/// ShellX: the bridge host backed by real Mac terminals (TerminalController / Workspace /
/// libghostty), ported from the W0 spike (`4e1ed7bc41:Sources/Mobile/ShellXBridgeSpike.swift`).
///
/// D7 projection rule: a daemon terminal bound while no other is bound projects the Mac's focused
/// terminal (`mode=attach`); every later one opens a new tab in the focused workspace
/// (`mode=create`). Unbinding never closes a Mac tab. Input goes to `ghostty_surface_text_input`
/// as the bytes arrived (it maps `\n` to `\r`); the bytes are never decoded as text.
@MainActor
final class TerminalControllerBridgeHost: ShellXBridgeHost {
    private struct State {
        var viewportGeneration = 0
        /// Last grid read from libghostty; reported while the surface is not drawable yet.
        var lastGrid: (cols: UInt16, rows: UInt16)
    }

    private let controller: TerminalController
    private var states: [BridgeBinding: State] = [:]

    init(controller: TerminalController = .shared) {
        self.controller = controller
    }

    func bind(hello: BridgeHello) -> BridgeBinding? {
        let fallbackGrid = (cols: max(hello.cols, 1), rows: max(hello.rows, 1))
        if states.isEmpty, let focused = controller.mobileCanonicalTerminalTarget(params: [:]) {
            let binding = BridgeBinding(connectionID: hello.connectionID, surfaceID: focused.target.surfaceID,
                                        workspaceID: focused.workspace.id, mode: "attach")
            states[binding] = State(lastGrid: fallbackGrid)
            return binding
        }
        // Remote-initiated create: a real libghostty tab in the focused workspace.
        guard let resolved = controller.mobileResolveWorkspaceAndSurface(params: [:], requireTerminal: false) else {
            return nil
        }
        let workspace = resolved.workspace
        guard let pane = workspace.bonsplitController.focusedPaneId ?? workspace.bonsplitController.allPaneIds.first,
              let panel = workspace.newTerminalSurface(
                  inPane: pane,
                  focus: true,
                  workingDirectory: hello.cwd,
                  autoRefreshMetadata: false,
                  preserveFocusWhenUnfocused: false,
                  allowTextBoxFocusDefault: false,
                  inheritStartupWork: false
              ),
              let created = controller.mobileCanonicalTerminalTarget(params: [
                  "workspace_id": workspace.id.uuidString,
                  "surface_id": panel.id.uuidString,
              ]) else { return nil }
        let binding = BridgeBinding(connectionID: hello.connectionID, surfaceID: created.target.surfaceID,
                                    workspaceID: workspace.id, mode: "create")
        states[binding] = State(lastGrid: fallbackGrid)
        return binding
    }

    func input(_ bytes: Data, binding: BridgeBinding) {
        guard !bytes.isEmpty, let target = liveTarget(binding),
              let surface = target.surface.liveSurfaceForGhosttyAccess(reason: "shellx.bridge.input") else { return }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
            ghostty_surface_text_input(surface, base, UInt(raw.count))
        }
    }

    func remoteResize(cols: UInt16, rows: UInt16, binding: BridgeBinding) {
        guard var state = states[binding] else { return }
        state.viewportGeneration += 1
        states[binding] = state
        // The remote viewer joins the Mac's shared sizing as one participant; the Mac decides
        // and the server echoes the resulting grid.
        _ = controller.v2MobileTerminalViewport(params: [
            "workspace_id": binding.workspaceID.uuidString,
            "surface_id": binding.surfaceID.uuidString,
            "client_id": Self.clientID(binding),
            "viewport_columns": Int(cols),
            "viewport_rows": Int(rows),
            "viewport_generation": state.viewportGeneration,
            "device_kind": "tui",
            "device_name": "ShellX remote",
        ])
    }

    func grid(binding: BridgeBinding) -> (cols: UInt16, rows: UInt16)? {
        guard var state = states[binding], let target = liveTarget(binding) else { return nil }
        if let surface = target.surface.liveSurfaceForGhosttyAccess(reason: "shellx.bridge.size") {
            let size = ghostty_surface_size(surface)
            if size.columns > 0, size.rows > 0 {
                state.lastGrid = (size.columns, size.rows)
                states[binding] = state
            }
        }
        return state.lastGrid
    }

    func snapshot(binding: BridgeBinding) -> Data? {
        guard binding.mode == "attach", let target = liveTarget(binding),
              let vt = target.surface.readBoundedScreenTailVT(maxRows: 200, maxBytes: 1 << 20) else { return nil }
        // Start the mirror from a clean screen; the tail VT ends at the cursor.
        return Data(("\u{1b}[H\u{1b}[2J" + vt).utf8)
    }

    func unbind(_ binding: BridgeBinding) {
        guard let state = states.removeValue(forKey: binding) else { return }
        _ = controller.v2MobileTerminalViewport(params: [
            "workspace_id": binding.workspaceID.uuidString,
            "surface_id": binding.surfaceID.uuidString,
            "client_id": Self.clientID(binding),
            "clear": true,
            "viewport_generation": state.viewportGeneration + 1,
        ])
    }

    private static func clientID(_ binding: BridgeBinding) -> String {
        "shellx-bridge-\(binding.connectionID)"
    }

    private func liveTarget(_ binding: BridgeBinding) -> ControlTerminalSocketTarget? {
        controller.mobileCanonicalTerminalTarget(params: [
            "workspace_id": binding.workspaceID.uuidString,
            "surface_id": binding.surfaceID.uuidString,
        ])?.target
    }
}

#if DEBUG
/// ShellX: temporary DEBUG-only bridge start for the Task 11 live check, enabled by
/// `SHELLX_REMOTE_MACHINES=1`. Task 13's remote service replaces it (and its AppDelegate calls).
@MainActor
enum ShellXBridgeDebugStart {
    private static var server: ShellXBridgeServer?

    static func startIfRequested(environment: [String: String]) {
        guard environment["SHELLX_REMOTE_MACHINES"] == "1", server == nil,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let paths = RemotePaths(bundleID: bundleID,
                                home: FileManager.default.homeDirectoryForCurrentUser,
                                temporaryDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        let candidate = ShellXBridgeServer(socket: paths.bridgeSocket, host: TerminalControllerBridgeHost())
        do {
            try candidate.start()
            server = candidate
        } catch {
            // StartError carries operation names, errno and reasons only (no paths, no payloads).
            Logger(subsystem: "pro.shellx.desktop", category: "remote-bridge")
                .error("bridge did not start: \(String(describing: error), privacy: .public)")
        }
    }

    static func stop() {
        server?.stop()
        server = nil
    }
}
#endif
