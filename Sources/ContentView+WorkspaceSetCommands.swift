import AppKit
import CmuxCommandPalette
import Foundation

extension ContentView {
    static let workspaceSetSaveCommandId = "palette.workspaceSet.save"
    static let workspaceSetDeleteCommandIdPrefix = "palette.workspaceSet.delete."

    func appendWorkspaceSetCommandContributions(to contributions: inout [CommandPaletteCommandContribution]) {
        let subtitle = String(localized: "command.workspaceSet.subtitle", defaultValue: "Workspace Sets")
        contributions.append(
            CommandPaletteCommandContribution(
                commandId: Self.workspaceSetSaveCommandId,
                title: { _ in String(localized: "command.workspaceSet.save.title", defaultValue: "Save Workspaces as Set…") },
                subtitle: { _ in subtitle },
                keywords: ["save", "workspace", "set", "group", "project", "folders", "session"],
                when: { $0.bool(CommandPaletteContextKeys.hasWorkspace) },
                enablement: { $0.bool(CommandPaletteContextKeys.hasWorkspace) }
            )
        )
        let openFormat = String(localized: "command.workspaceSet.open.title", defaultValue: "Open Workspace Set: %@")
        let deleteFormat = String(localized: "command.workspaceSet.delete.title", defaultValue: "Delete Workspace Set: %@")
        for name in workspaceSetNamesForCommandPalette() {
            contributions.append(
                CommandPaletteCommandContribution(
                    commandId: Self.workspaceSetCommandId(prefix: "palette.workspaceSet.open.", name: name),
                    title: { _ in String.localizedStringWithFormat(openFormat, name) },
                    subtitle: { _ in subtitle },
                    keywords: ["open", "workspace", "set", "project", "folders", "session", name]
                )
            )
            contributions.append(
                CommandPaletteCommandContribution(
                    commandId: Self.workspaceSetCommandId(prefix: Self.workspaceSetDeleteCommandIdPrefix, name: name),
                    title: { _ in String.localizedStringWithFormat(deleteFormat, name) },
                    subtitle: { _ in subtitle },
                    keywords: ["delete", "remove", "workspace", "set", name]
                )
            )
        }
    }

    func registerWorkspaceSetCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        registry.register(commandId: Self.workspaceSetSaveCommandId) {
            presentWorkspaceSetSavePrompt()
        }
        for name in workspaceSetNamesForCommandPalette() {
            registry.register(commandId: Self.workspaceSetCommandId(prefix: "palette.workspaceSet.open.", name: name)) {
                guard let workspaceSet = try? WorkspaceSetStore().set(named: name) else {
                    NSSound.beep()
                    return
                }
                tabManager.openWorkspaceSet(workspaceSet)
            }
            registry.register(commandId: Self.workspaceSetCommandId(prefix: Self.workspaceSetDeleteCommandIdPrefix, name: name)) {
                presentWorkspaceSetDeleteConfirmation(name: name)
            }
        }
    }

    func presentWorkspaceSetSavePrompt() {
        let captured = tabManager.captureWorkspaceSet(named: "")
        guard !captured.workspaces.isEmpty else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "dialog.workspaceSet.save.title", defaultValue: "Save Workspaces as Set")
        alert.informativeText = tabManager.sidebarSelectedWorkspaceIds.count >= 2
            ? String(localized: "dialog.workspaceSet.save.messageSelected", defaultValue: "The set saves the selected workspaces. Open it later to bring them all back.")
            : String(localized: "dialog.workspaceSet.save.messageAll", defaultValue: "The set saves every workspace in this window. Open it later to bring them all back.")
        alert.addButton(withTitle: String(localized: "dialog.workspaceSet.save.confirm", defaultValue: "Save"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = String(localized: "dialog.workspaceSet.save.placeholder", defaultValue: "Set name")
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runCmuxModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            presentWorkspaceSetError(
                title: workspaceSetSaveErrorTitle(),
                message: String(localized: "dialog.workspaceSet.error.blankName", defaultValue: "Enter a name before saving the set.")
            )
            return
        }

        let store = WorkspaceSetStore()
        do {
            let exists = try store.set(named: name) != nil
            if exists, !confirmWorkspaceSetOverwrite(name: name) { return }
            try store.save(CmuxWorkspaceSet(name: name, workspaces: captured.workspaces), overwrite: exists)
        } catch {
            presentWorkspaceSetError(title: workspaceSetSaveErrorTitle(), message: workspaceSetErrorMessage(error))
        }
    }

    private func presentWorkspaceSetDeleteConfirmation(name: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "dialog.workspaceSet.delete.title", defaultValue: "Delete Workspace Set?")
        let format = String(localized: "dialog.workspaceSet.delete.message", defaultValue: "“%@” will be removed from your saved sets. Open workspaces stay open.")
        alert.informativeText = String.localizedStringWithFormat(format, name)
        alert.addButton(withTitle: String(localized: "dialog.workspaceSet.delete.confirm", defaultValue: "Delete"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
        guard alert.runCmuxModal() == .alertFirstButtonReturn else { return }

        do {
            try WorkspaceSetStore().delete(named: name)
        } catch {
            presentWorkspaceSetError(
                title: String(localized: "dialog.workspaceSet.error.deleteTitle", defaultValue: "Workspace Set Not Deleted"),
                message: workspaceSetErrorMessage(error)
            )
        }
    }

    private func confirmWorkspaceSetOverwrite(name: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "dialog.workspaceSet.overwrite.title", defaultValue: "Replace Workspace Set?")
        let format = String(localized: "dialog.workspaceSet.overwrite.message", defaultValue: "A set named “%@” already exists. Replace it?")
        alert.informativeText = String.localizedStringWithFormat(format, name)
        alert.addButton(withTitle: String(localized: "dialog.workspaceSet.overwrite.confirm", defaultValue: "Replace"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
        return alert.runCmuxModal() == .alertFirstButtonReturn
    }

    private func presentWorkspaceSetError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK"))
        _ = alert.runCmuxModal()
    }

    private func workspaceSetSaveErrorTitle() -> String {
        String(localized: "dialog.workspaceSet.error.saveTitle", defaultValue: "Workspace Set Not Saved")
    }

    private func workspaceSetErrorMessage(_ error: Error) -> String {
        switch error as? WorkspaceSetStoreError {
        case .blankName:
            return String(localized: "dialog.workspaceSet.error.blankName", defaultValue: "Enter a name before saving the set.")
        case .notFound:
            return String(localized: "dialog.workspaceSet.error.notFound", defaultValue: "That workspace set could not be found.")
        case .corruptFile:
            return String(localized: "dialog.workspaceSet.error.corruptFile", defaultValue: "The workspace sets file could not be read. Check it and try again.")
        case .duplicateName, nil:
            return String(localized: "dialog.workspaceSet.error.unknown", defaultValue: "The workspace set request could not be completed. Try again.")
        }
    }

    private func workspaceSetNamesForCommandPalette() -> [String] {
        ((try? WorkspaceSetStore().list()) ?? []).map(\.name)
    }

    private static func workspaceSetCommandId(prefix: String, name: String) -> String {
        let encodedName = Data(name.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return prefix + encodedName
    }
}
