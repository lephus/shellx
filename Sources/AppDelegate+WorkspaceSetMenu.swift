import AppKit
import Foundation

@MainActor
extension AppDelegate {
    private final class WorkspaceSetMenuActionBox: NSObject {
        let windowId: UUID
        let setName: String

        init(windowId: UUID, setName: String) {
            self.windowId = windowId
            self.setName = setName
        }
    }

    func workspaceSetOpenMenuItem(setNames: [String], windowId: UUID) -> NSMenuItem? {
        guard !setNames.isEmpty else { return nil }
        let parent = NSMenuItem(
            title: String(localized: "menu.workspaceSet.open", defaultValue: "Open Workspace Set"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        for setName in setNames {
            let item = NSMenuItem(
                title: setName,
                action: #selector(performWorkspaceSetMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = WorkspaceSetMenuActionBox(windowId: windowId, setName: setName)
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func performWorkspaceSetMenuItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? WorkspaceSetMenuActionBox,
              let context = mainWindowContexts.values.first(where: { $0.windowId == box.windowId }),
              resolvedWindow(for: context) != nil,
              let workspaceSet = try? WorkspaceSetStore().set(named: box.setName) else {
            NSSound.beep()
            return
        }
        context.tabManager.openWorkspaceSet(workspaceSet)
    }
}
