import ShellXLinkCore

/// The host's terminals as phones view them (PROTOCOL.md section 11). A host that has one offers `terminal_view`.
public protocol TerminalViewSource: Sendable {
    /// Starts a view of `terminalId` for a phone that can show `cols` x `rows` (already clamped into
    /// `ShellXLink.terminalColumns` and `ShellXLink.terminalRows`). `.notOpened(.notFound)` for a terminal that is not in
    /// a local workspace the host lists, `.notOpened(.refused)` when remote control is blocked, `.notOpened(.failed)`
    /// when it could not start one. Never `.busy` (the host's own rule) nor `.ok`.
    func openView(terminalId: String, cols: Int, rows: Int) async -> TerminalViewOpenResult
}

/// One open view: what a phone's `terminal.view.open` started. The host calls each method from one task at a time.
public protocol TerminalView: Sendable {
    /// The next frame of the view, or its end. The first call returns a snapshot carrying up to
    /// `ShellXLink.terminalHistoryRowBudget` history rows on the main screen. Every later call returns a delta computed
    /// against the frame the call before returned, or a snapshot (new size, other screen, new palette, or after
    /// `requestSnapshot()`); it suspends until the terminal changed, and paces itself. It never returns `.history`
    /// frames (the host makes those). The host calls it again only when no frame it made is waiting, so a slow phone
    /// makes the view merge changes. It returns promptly when its task is cancelled or after `close()`.
    func nextFrame() async -> TerminalViewEvent
    /// Makes the frame of the next `nextFrame()` call that starts after this returns a snapshot.
    func requestSnapshot() async
    /// Applies the phone's units in order; the host has checked them (`TerminalInputCheck`). A unit, key or modifier the
    /// view does not know is skipped. Typing is the phone's activity for the terminal's size. When remote control
    /// becomes blocked (device management), the view ends: `nextFrame()` returns `.ended(.refused)` and later input is
    /// not applied. A `scroll` unit acts only while the alternate screen is active.
    func input(_ units: [TerminalInputUnit]) async
    /// The phone's size changed (already clamped).
    func resize(cols: Int, rows: Int) async
    /// The phone stopped viewing: the terminal goes back to the Mac's size. Called once.
    func close() async
}

public enum TerminalViewOpenResult: Sendable {
    case opened(any TerminalView)
    case notOpened(TerminalViewOpenOutcome)
}

public enum TerminalViewEvent: Equatable, Sendable {
    case frame(TerminalGridFrame)
    case ended(TerminalViewEndReason)
}

/// A terminal push from the host, in arrival order (`LinkClient.terminalPushes`).
public enum TerminalViewPush: Equatable, Sendable {
    /// This client's `terminal.view.open` for `terminalId` was answered `ok`: start a fresh `TerminalFrameAssembler`;
    /// every frame of that terminal after this belongs to the new view.
    case opened(terminalId: String)
    case frame(terminalId: String, part: TerminalFramePart)
    case ended(terminalId: String, reason: TerminalViewEndReason)
}
