import CoreGraphics
import Foundation

/// The status pill a sidebar row shows next to its title: "waiting",
/// "running", "done" or "error". Idle rows show no pill. The app maps its
/// compact status glyph onto this (`SidebarStatusPill.from(_:)`).
public enum SidebarStatusPill: Equatable, Hashable, Sendable, CaseIterable {
    case waiting
    case running
    case done
    case error

    /// Pill fill is the status color at this opacity; no gradients or glows.
    public static let fillAlpha: Double = 0.12

    /// The status color (fill is this at `fillAlpha`).
    public var color: ShellXColor {
        switch self {
        case .waiting: return ShellXPalette.primary
        case .running: return ShellXPalette.running
        case .done: return ShellXPalette.done
        case .error: return ShellXPalette.error
        }
    }

    /// Label color: the status color, except waiting uses the lighter
    /// primary text tone for contrast on its soft fill.
    public var textColor: ShellXColor {
        switch self {
        case .waiting: return ShellXPalette.primaryText
        case .running, .done, .error: return color
        }
    }

    /// Localized from the app's catalog (`bundle: .main`); English elsewhere.
    public var title: String {
        switch self {
        case .waiting:
            return String(localized: "sidebar.pill.waiting", defaultValue: "waiting", bundle: .main)
        case .running:
            return String(localized: "sidebar.pill.running", defaultValue: "running", bundle: .main)
        case .done:
            return String(localized: "sidebar.pill.done", defaultValue: "done", bundle: .main)
        case .error:
            return String(localized: "sidebar.pill.error", defaultValue: "error", bundle: .main)
        }
    }
}

/// Fixed geometry for the machine section header row. Its height never
/// depends on the title: long names truncate with an ellipsis instead.
public enum SidebarMachineHeaderLayout {
    public static let height: CGFloat = 28

    public static func height(forTitle title: String) -> CGFloat {
        _ = title
        return height
    }
}
