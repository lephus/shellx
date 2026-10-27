import Foundation

/// Seam for the final-review regression tests; the fix fills it in.
public struct PermissionLayout: Equatable, Sendable {
    public var buttons: [PendingAction]
    public var menu: [PendingAction]

    public init(_ actions: [PendingAction]) {
        buttons = []
        menu = []
    }
}
