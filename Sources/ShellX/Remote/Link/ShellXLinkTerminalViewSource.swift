import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// ShellX: the Mac's terminals as phones view them (`terminal_view`, PROTOCOL.md 11): only terminals of local workspaces
/// the phone's list holds, one Link view per phone, ended `gone` when the list loses the terminal. Never logs ids or titles.
@MainActor
final class ShellXLinkTerminalViewSource: TerminalViewSource {
    struct Mac {
        /// The listed workspace whose terminals include `terminal`; nil when none lists it.
        var listedWorkspace: @MainActor (_ terminal: UUID) -> UUID?
        /// Makes a listed terminal ready for a viewer (a never-shown terminal starts, a hibernated agent wakes) and
        /// returns the surface to view; nil when there is none.
        var prepare: @MainActor (_ workspace: UUID, _ terminal: UUID) -> UUID?
        var terminal: @MainActor (_ surface: UUID) -> ShellXLinkTerminalView.Terminal
        var sizing: @MainActor (_ surface: UUID, _ clientID: String) -> ShellXLinkTerminalView.Sizing
        var isBlocked: @MainActor () -> Bool
        /// Calls `onChange` after each change of the listed workspaces until the returned function runs.
        var listChanges: @MainActor (_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void
    }

    private struct OpenView {
        let view: ShellXLinkTerminalView
        let terminal: UUID
    }

    private let mac: Mac
    private let frameSinks: any MobileTerminalFrameSinkRegistry
    private let notificationCenter: NotificationCenter
    private var views: [ObjectIdentifier: OpenView] = [:]
    private var stopWatching: (@MainActor () -> Void)?

    init(
        mac: Mac, frameSinks: any MobileTerminalFrameSinkRegistry, notificationCenter: NotificationCenter = .default
    ) {
        self.mac = mac
        self.frameSinks = frameSinks
        self.notificationCenter = notificationCenter
    }

    var openViewCount: Int { views.count }

    func openView(terminalId: String, cols: Int, rows: Int) async -> TerminalViewOpenResult {
        guard !mac.isBlocked() else { return .notOpened(.refused) }
        guard let terminal = UUID(uuidString: terminalId), let workspace = mac.listedWorkspace(terminal) else {
            return .notOpened(.notFound)
        }
        guard let surface = mac.prepare(workspace, terminal) else { return .notOpened(.failed) }
        let clientID = TerminalController.shellXLinkSizingClientIDPrefix + UUID().uuidString.lowercased()
        let view = ShellXLinkTerminalView(
            surfaceID: surface, terminal: mac.terminal(surface), sizing: mac.sizing(surface, clientID),
            frameSinks: frameSinks, isBlocked: mac.isBlocked, notificationCenter: notificationCenter,
            onClose: { [weak self] view in self?.forget(view) }
        )
        view.open(cols: cols, rows: rows)
        views[ObjectIdentifier(view)] = OpenView(view: view, terminal: terminal)
        if stopWatching == nil {
            stopWatching = mac.listChanges { [weak self] in self?.listChanged() }
        }
        return .opened(view)
    }

    /// Ends with `gone` every view whose terminal the list no longer holds.
    private func listChanged() {
        for open in views.values where mac.listedWorkspace(open.terminal) == nil {
            open.view.end(.gone)
        }
    }

    private func forget(_ view: ShellXLinkTerminalView) {
        views.removeValue(forKey: ObjectIdentifier(view))
        guard views.isEmpty, let stop = stopWatching else { return }
        stopWatching = nil
        stop()
    }
}
