import Foundation

/// What a share exposes of one workspace. Implemented by the app on the main actor.
@MainActor
public protocol ShareSource: AnyObject, Sendable {
    var panes: [SharePane] { get }
    var activePane: String? { get }
    /// Grid size and a VT stream that redraws the pane from a cleared screen; nil for non-terminals.
    func snapshot(pane: String) -> (cols: Int, rows: Int, vt: Data)?
    /// `sink` may be called from any thread (libghostty IO). Drop the returned token to unsubscribe.
    func subscribe(pane: String, _ sink: @escaping @Sendable (Data) -> Void) -> AnyObject
    func input(pane: String, _ bytes: Data)
    var onPanesChanged: (() -> Void)? { get set }
}

public struct ShareViewer: Sendable, Equatable {
    /// The relay circuit id.
    public let id: String
    public let label: String
    public let connectedAt: Date

    public init(id: String, label: String, connectedAt: Date) {
        self.id = id; self.label = label; self.connectedAt = connectedAt
    }
}
