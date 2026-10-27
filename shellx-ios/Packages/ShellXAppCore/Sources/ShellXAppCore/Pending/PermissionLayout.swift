import Foundation

/// How a permission card lays out its actions (ruling P3-R4): Deny and Allow (`once`, the primary
/// button) in the row, the lasting grants ("Always allow", "All tools") in the "…" menu. A lasting
/// grant is never the one-tap primary button, also when the Mac does not offer `once`. The card only
/// renders this.
public struct PermissionLayout: Equatable, Sendable {
    /// The buttons in the row, in order.
    public var buttons: [PendingAction]
    /// The actions in the "…" menu, in order.
    public var menu: [PendingAction]

    /// The layout of the permission actions among `actions`; any other action is left out.
    public init(_ actions: [PendingAction]) {
        buttons = [PendingAction.deny, .allowOnce].filter { actions.contains($0) }
        menu = [PendingAction.allowAlways, .allowAllTools].filter { actions.contains($0) }
    }
}
