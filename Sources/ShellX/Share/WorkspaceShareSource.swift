import CmuxTerminal
import Combine
import Foundation
import GhosttyKit
import ShellXRemoteCore

/// ShellX: libghostty access for a shared terminal pane, swapped for a fake in tests (a unit test
/// has no drawable surface).
@MainActor
protocol ShellXShareTerminalIO: AnyObject {
    func grid(_ panel: TerminalPanel) -> (cols: Int, rows: Int)?
    func screenTailVT(_ panel: TerminalPanel) -> String?
    func write(_ bytes: Data, to panel: TerminalPanel)
}

/// The real surfaces, as `TerminalControllerBridgeHost` reaches them.
@MainActor
final class GhosttyShareTerminalIO: ShellXShareTerminalIO {
    func grid(_ panel: TerminalPanel) -> (cols: Int, rows: Int)? {
        guard let surface = panel.surface.liveSurfaceForGhosttyAccess(reason: "shellx.share.size") else { return nil }
        let size = ghostty_surface_size(surface)
        guard size.columns > 0, size.rows > 0 else { return nil }
        return (Int(size.columns), Int(size.rows))
    }

    func screenTailVT(_ panel: TerminalPanel) -> String? {
        panel.surface.readBoundedScreenTailVT(maxRows: 200, maxBytes: 1 << 20)
    }

    /// The bytes as they arrived (`ghostty_surface_text_input` maps `\n` to `\r`); never decoded.
    func write(_ bytes: Data, to panel: TerminalPanel) {
        guard !bytes.isEmpty,
              let surface = panel.surface.liveSurfaceForGhosttyAccess(reason: "shellx.share.input") else { return }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
            ghostty_surface_text_input(surface, base, UInt(raw.count))
        }
    }
}

/// ShellX: one workspace as a `ShareSource` (spec §7.3, ruling R7). Panes are the workspace's panels
/// in bonsplit order; terminals are shared, browser and Agent Chat panels (and every other panel
/// kind) are placeholders the viewer cannot read. Pane ids are the panel (= surface) UUIDs.
@MainActor
final class WorkspaceShareSource: ShareSource {
    /// Grid reported before a surface is drawable.
    static let fallbackGrid = (cols: 80, rows: 24)
    /// How often a live share re-reads grids and titles to notice resizes.
    static let pollInterval: TimeInterval = 1

    private weak var workspace: Workspace?
    private let io: any ShellXShareTerminalIO
    private var lastPanes: [SharePane] = []
    private var observers: Set<AnyCancellable> = []
    private var poll: Timer?

    var onPanesChanged: (() -> Void)? {
        didSet { onPanesChanged == nil ? stopObserving() : startObserving() }
    }

    /// `io` nil: the real surfaces (a default argument would be built outside the main actor).
    init(workspace: Workspace, io: (any ShellXShareTerminalIO)? = nil) {
        self.workspace = workspace
        self.io = io ?? GhosttyShareTerminalIO()
    }

    var workspaceID: UUID? { workspace?.id }

    var panes: [SharePane] {
        guard let workspace else { return [] }
        return workspace.orderedPanelIds.compactMap { id in
            guard let panel = workspace.panels[id] else { return nil }
            let title = workspace.panelTitle(panelId: id) ?? panel.displayTitle
            let kind = Self.kind(of: panel.panelType)
            var grid = (cols: 0, rows: 0)
            if kind == .terminal, let terminal = panel as? TerminalPanel {
                grid = io.grid(terminal) ?? Self.fallbackGrid
            }
            return SharePane(id: id.uuidString, title: title, kind: kind, cols: grid.cols, rows: grid.rows)
        }
    }

    var activePane: String? {
        guard let workspace else { return nil }
        let ids = workspace.orderedPanelIds
        if let focused = workspace.focusedPanelId, ids.contains(focused) { return focused.uuidString }
        return ids.first?.uuidString
    }

    func snapshot(pane: String) -> (cols: Int, rows: Int, vt: Data)? {
        guard let terminal = terminalPanel(pane) else { return nil }
        let grid = io.grid(terminal) ?? Self.fallbackGrid
        // Start the viewer from a cleared screen; the tail VT ends at the cursor.
        let vt = "\u{1b}[H\u{1b}[2J" + (io.screenTailVT(terminal) ?? "")
        return (grid.cols, grid.rows, Data(vt.utf8))
    }

    func subscribe(pane: String, _ sink: @escaping @Sendable (Data) -> Void) -> AnyObject {
        guard let terminal = terminalPanel(pane) else { return ShellXShareTeeSubscription(surfaceID: nil, sink: sink) }
        return ShellXShareTeeSubscription(surfaceID: terminal.id, sink: sink)
    }

    func input(pane: String, _ bytes: Data) {
        guard !bytes.isEmpty, let terminal = terminalPanel(pane) else { return }
        io.write(bytes, to: terminal)
    }

    static func kind(of type: PanelType) -> SharePaneKind {
        switch type {
        case .terminal: return .terminal
        case .agentSession: return .agent
        default: return .browser
        }
    }

    private func terminalPanel(_ pane: String) -> TerminalPanel? {
        guard let id = UUID(uuidString: pane) else { return nil }
        return workspace?.panels[id] as? TerminalPanel
    }

    // MARK: Pane changes

    private func startObserving() {
        guard observers.isEmpty, let workspace else { return }
        lastPanes = panes
        // Both publishers send on the main thread before the change is fully applied; read on the next turn.
        workspace.panelsPublisher.map { _ in () }
            .merge(with: workspace.paneLayoutVersionPublisher.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.checkPanes() } }
            .store(in: &observers)
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPanes() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func stopObserving() {
        observers.removeAll()
        poll?.invalidate()
        poll = nil
    }

    /// Fires `onPanesChanged` only when the list, a title or a grid actually changed.
    func checkPanes() {
        let now = panes
        guard now != lastPanes else { return }
        lastPanes = now
        onPanesChanged?()
    }
}

/// The token `subscribe` returns: while it lives, the surface's PTY output reaches `sink` through
/// `ShellXBridgeTee`. The registry holds the sink strongly, so the sink is a separate object the
/// token unregisters on deinit.
final class ShellXShareTeeSubscription: @unchecked Sendable {
    private final class Sink: ShellXTeeSink, @unchecked Sendable {
        let deliver: @Sendable (Data) -> Void
        init(_ deliver: @escaping @Sendable (Data) -> Void) { self.deliver = deliver }
        func teeOutput(_ bytes: Data) { deliver(bytes) }
    }

    private let surfaceID: UUID?
    private let sink: Sink

    init(surfaceID: UUID?, sink: @escaping @Sendable (Data) -> Void) {
        self.surfaceID = surfaceID
        self.sink = Sink(sink)
        if let surfaceID { ShellXRemoteCore.ShellXBridgeTee.register(self.sink, surfaceID: surfaceID) }
    }

    deinit {
        if let surfaceID { ShellXRemoteCore.ShellXBridgeTee.unregister(sink, surfaceID: surfaceID) }
    }
}
