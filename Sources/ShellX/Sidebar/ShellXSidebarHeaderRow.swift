import AppKit
import Foundation
import ShellXBrand

/// The non-workspace rows ShellX adds to the AppKit sidebar table: the brand
/// header at the top, the "Sign in to see your other machines" row while the
/// remote UI is on and signed out, and one header per machine section. They
/// are not selectable, draggable or drop targets.
enum ShellXSidebarHeaderRow: Equatable {
    case brand
    case signIn
    case machine(SidebarMachineHeaderModel)

    /// Fixed heights: neither header grows with its text (long names truncate).
    var rowHeight: CGFloat {
        switch self {
        case .brand:
            return ShellXSidebarHeaderMetrics.brandHeight
        case .signIn:
            return ShellXSidebarHeaderMetrics.signInHeight
        case .machine(let header):
            return SidebarWorkspaceTableRowHeightCalculator.height(forMachineHeaderTitle: header.title)
        }
    }

    var rowId: SidebarWorkspaceRenderItemID {
        switch self {
        case .brand:
            return .shellXBrandHeader
        case .signIn:
            return .shellXSignInRow
        case .machine(let header):
            return .machine(header.key.stableID)
        }
    }

    /// Rows carry a workspace id; header rows get one that matches no
    /// workspace, so selection, close and drop lookups find nothing.
    var placeholderWorkspaceId: UUID {
        switch self {
        case .brand:
            return SidebarWorkspaceRenderItemID.shellXBrandHeaderUUID
        case .signIn:
            return SidebarWorkspaceRenderItemID.shellXSignInRowUUID
        case .machine(let header):
            return header.key.stableID
        }
    }
}

enum ShellXSidebarHeaderMetrics {
    /// Brand line (logo + name) plus the "YOUR MACHINES" line.
    static let brandHeight: CGFloat = 62
    static let brandLineHeight: CGFloat = 36
    static let logoSide: CGFloat = 22
    static let iconSide: CGFloat = 14
    static let onlineDotSide: CGFloat = 6
    static let addButtonSide: CGFloat = 18
    /// The sign-in row has the machine header's fixed height.
    static let signInHeight: CGFloat = SidebarMachineHeaderLayout.height
    /// The remote header's trailing "Request access" button.
    static let actionButtonHeight: CGFloat = 18
}

/// Cells that render a `ShellXSidebarHeaderRow`.
@MainActor
protocol ShellXSidebarHeaderCell: NSView {
    func configure(header: ShellXSidebarHeaderRow)
}

@MainActor
enum ShellXSidebarHeaderCells {
    /// Dequeues (or creates) and configures the cell for a header row.
    static func cell(
        for header: ShellXSidebarHeaderRow,
        in tableView: NSTableView,
        owner: Any?
    ) -> NSView {
        let cell: NSView & ShellXSidebarHeaderCell
        switch header {
        case .brand:
            cell = tableView.makeView(
                withIdentifier: SidebarBrandHeaderCellView.reuseIdentifier,
                owner: owner
            ) as? SidebarBrandHeaderCellView ?? SidebarBrandHeaderCellView()
        case .signIn:
            cell = tableView.makeView(
                withIdentifier: SidebarSignInRowCellView.reuseIdentifier,
                owner: owner
            ) as? SidebarSignInRowCellView ?? SidebarSignInRowCellView()
        case .machine:
            cell = tableView.makeView(
                withIdentifier: SidebarMachineHeaderCellView.reuseIdentifier,
                owner: owner
            ) as? SidebarMachineHeaderCellView ?? SidebarMachineHeaderCellView()
        }
        cell.configure(header: header)
        return cell
    }
}
