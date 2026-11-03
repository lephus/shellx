import AppKit
import CmuxTerminal
import Foundation
import ShellXAutomations

extension AppDelegate {
    /// The library the sidebar button counts, once Automations started.
    var shellXAutomationsLibrary: ShellXAutomationsLibrary? { shellXAutomations?.library }

    /// Builds the Automations graph and starts watching the store. Skipped under XCTest so
    /// tests never read or reconcile the user's real automations and launchd jobs.
    func startShellXAutomations() {
        guard shellXAutomations == nil,
              !isRunningUnderXCTest(ProcessInfo.processInfo.environment) else { return }
        let runtime = ShellXAutomationsRuntime(
            bundle: .main,
            home: FileManager.default.homeDirectoryForCurrentUser,
            processEnvironment: ProcessInfo.processInfo.environment
        )
        shellXAutomations = runtime
        runtime.library.startWatching()
        flushShellXAutomationsOpenQueue()
    }

    /// Opens every `<scheme>://automations[/<id>]` link for this app's own scheme and returns the
    /// other URLs. A link that arrives during launch waits until Automations started and the
    /// session was restored.
    func handleShellXAutomationsURLs(_ urls: [URL]) -> [URL] {
        let scheme = ShellXAppURLScheme(infoDictionary: Bundle.main.infoDictionary).scheme
        var others: [URL] = []
        var focus: ShellXAutomationsURL?
        for url in urls {
            if let link = ShellXAutomationsURL(url, scheme: scheme) {
                focus = link
            } else {
                others.append(url)
            }
        }
        if let focus {
            shellXAutomationsOpenQueue.submit(focus, isReady: isReadyToOpenShellXAutomations) { [weak self] id in
                self?.openShellXAutomations(focusId: id)
            }
        }
        return others
    }

    /// Opens a link that waited for launch, once Automations started and no restore is pending.
    func flushShellXAutomationsOpenQueue() {
        shellXAutomationsOpenQueue.flush(isReady: isReadyToOpenShellXAutomations) { [weak self] id in
            self?.openShellXAutomations(focusId: id)
        }
    }

    private var isReadyToOpenShellXAutomations: Bool {
        shellXAutomations != nil && !shouldDeferNavigationURLRequestsForStartupRestore
    }

    /// Shows the Automations tab in the active window's selected workspace, reusing an open
    /// one there, and focuses `focusId`'s card when given.
    func openShellXAutomations(focusId: String?) {
        guard let runtime = shellXAutomations else { return }
        let context: MainWindowContext? = {
            if let existing = preferredRegisteredMainWindowContext(preferredWindow: NSApp.keyWindow ?? NSApp.mainWindow) {
                return existing
            }
            let windowId = createMainWindow()
            return mainWindowContexts.values.first { $0.windowId == windowId }
        }()
        guard let context else { return }
        if let window = context.window ?? windowForMainWindowId(context.windowId) {
            bringToFront(window)
            setActiveMainWindow(window)
        }
        guard let workspace = context.tabManager.selectedWorkspace
            ?? context.tabManager.addWorkspaceIfActive(select: true) else { return }

        if let panel = workspace.shellXAutomationsPanel {
            workspace.focusPanel(panel.id)
            panel.controller.focus(id: focusId)
            return
        }
        guard let paneId = workspace.bonsplitController.focusedPaneId
            ?? workspace.bonsplitController.allPaneIds.first else { return }
        let controller = runtime.makeController(
            terminalOpener: { [weak self] automation in
                self?.openShellXAutomationSessionInTerminal(automation)
            },
            fileOpener: { url in
                NSWorkspace.shared.open(url)
            }
        )
        controller.focus(id: focusId)
        workspace.newShellXAutomationsSurface(inPane: paneId, controller: controller, focus: true)
    }

    /// Opens a terminal tab in the selected workspace that resumes the automation's last
    /// Claude Code session in its working folder.
    private func openShellXAutomationSessionInTerminal(_ automation: ShellXAutomation) {
        guard let sessionId = automation.lastRun?.sessionId, !sessionId.isEmpty,
              let context = preferredRegisteredMainWindowContext(preferredWindow: NSApp.keyWindow ?? NSApp.mainWindow),
              let workspace = context.tabManager.selectedWorkspace,
              let paneId = workspace.bonsplitController.focusedPaneId
                ?? workspace.bonsplitController.allPaneIds.first else { return }
        let directory = automation.workingDirectory ?? automation.directory.path
        workspace.newTerminalSurface(
            inPane: paneId,
            focus: true,
            workingDirectory: directory,
            initialInput: "claude --resume \(sessionId.terminalShellEscaped)\n"
        )
    }
}
