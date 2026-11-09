import CmuxTerminal
import Foundation

extension ShellXLinkTerminalView.Terminal {
    /// The terminal `surfaceID` names, resolved again on every call so a terminal that closed is simply gone.
    @MainActor
    static func live(surfaceID: UUID) -> Self {
        Self(
            surface: { GhosttyApp.terminalSurfaceRegistry.terminalSurface(id: surfaceID) },
            type: { text in
                _ = TerminalController.shared.terminalSocketTarget(surfaceID: surfaceID)?.sendInputResult(text)
            },
            press: { keyName in
                TerminalController.shared.terminalSocketTarget(surfaceID: surfaceID)?.sendNamedKeyResult(keyName).accepted ?? false
            },
            paste: { text in
                _ = TerminalController.shared.terminalSocketTarget(surfaceID: surfaceID)?.sendTextResult(text)
            },
            // The two calls of `v2MobileTerminalScroll`: the wheel, then a note that the screen may have changed.
            scroll: { lines, column, row in
                guard let target = TerminalController.shared.terminalSocketTarget(surfaceID: surfaceID) else { return }
                target.surface.mobileScroll(deltaLines: Double(lines), col: column, row: row)
                MobileTerminalRenderObserver.shared.noteTerminalBytes(surfaceID: surfaceID)
            }
        )
    }
}

extension ShellXLinkTerminalView.Sizing {
    /// The phone's part in the terminal's shared sizing (`TerminalController+ShellXLinkSizing.swift`).
    @MainActor
    static func live(surfaceID: UUID, clientID: String) -> Self {
        Self(
            attach: { cols, rows in
                TerminalController.shared.shellXLinkSizingAttach(
                    surfaceID: surfaceID, clientID: clientID, columns: cols, rows: rows
                )
            },
            resize: { cols, rows in
                TerminalController.shared.shellXLinkSizingResize(
                    surfaceID: surfaceID, clientID: clientID, columns: cols, rows: rows
                )
            },
            input: { apply in
                TerminalController.shared.performRemoteParticipantInput(surfaceID: surfaceID, clientID: clientID, apply)
            },
            detach: {
                TerminalController.shared.shellXLinkSizingDetach(surfaceID: surfaceID, clientID: clientID)
            }
        )
    }
}
