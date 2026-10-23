import AppKit

/// Watches what a sidebar cell's selection paint depends on, so the cell can
/// repaint when it changes: its window becoming or resigning key or main,
/// the app activating or resigning, system colors, and accessibility display
/// options.
///
/// Selected rows dim while their window is inactive (ShellX's tinted
/// selection and the subtle left-rail wash), so workspace rows and group
/// headers observe the window they move into and stop when they leave it.
@MainActor
final class SidebarSelectionChromeObserver {
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?

    /// Whether selection in `window` paints at full strength: the app is
    /// active and the window is key or main. Outside a window it counts as
    /// emphasized while the app is active.
    static func isSelectionEmphasized(in window: NSWindow?) -> Bool {
        NSApp.isActive && (window.map { $0.isKeyWindow || $0.isMainWindow } ?? true)
    }

    /// Replaces the observed window; a nil window only stops observing.
    /// `repaint` runs on the main queue after each change.
    func observe(_ window: NSWindow?, repaint: @escaping @Sendable (Notification) -> Void) {
        stopObserving()
        guard let window else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main, using: repaint),
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main, using: repaint),
            center.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main, using: repaint),
            center.addObserver(forName: NSWindow.didResignMainNotification, object: window, queue: .main, using: repaint),
            center.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main, using: repaint),
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: repaint),
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: repaint)
        ]
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main,
            using: repaint
        )
    }

    /// Removes every observer this instance registered.
    func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObserver.map { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObserver = nil
    }
}
