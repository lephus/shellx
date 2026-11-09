import CoreGraphics
import Foundation

/// Sizes of the terminal pane: the grid the phone asks for, the scale that fits a wider grid, and alternate-screen scroll
/// lines.
public enum TerminalGeometry {
    public static let padding: CGFloat = 4
    public static let maxZoom: CGFloat = 2

    /// The grid the phone asks for: what fits `viewport` at the default font, whose cell is `cell`; at least 1 × 1.
    public static func phoneGrid(viewport: CGSize, cell: CGSize) -> (cols: Int, rows: Int) {
        guard cell.width > 0, cell.height > 0 else { return (1, 1) }
        let cols = Int(((viewport.width - 2 * padding) / cell.width).rounded(.down))
        let rows = Int(((viewport.height - 2 * padding) / cell.height).rounded(.down))
        return (max(1, cols), max(1, rows))
    }

    /// The scale that fits `cols` columns into `viewportWidth`; 1 when they fit already (never larger than 1).
    public static func fitScale(cols: Int, cell: CGSize, viewportWidth: CGFloat) -> CGFloat {
        let content = CGFloat(max(cols, 1)) * cell.width
        guard content > 0 else { return 1 }
        return min(1, max(viewportWidth - 2 * padding, 1) / content)
    }

    /// Whole lines of a vertical pan on the alternate screen: `carry + translation` over `lineHeight × scale`, truncated toward
    /// zero (positive for a finger moving down, toward older content); the rest carries over.
    public static func scrollLines(translation: CGFloat, carry: CGFloat, lineHeight: CGFloat, scale: CGFloat) -> (lines: Int, carry: CGFloat) {
        let total = carry + translation
        let line = lineHeight * scale
        guard line > 0, total.isFinite else { return (0, 0) }
        let lines = (total / line).rounded(.towardZero)
        return (Int(lines), total - lines * line)
    }
}

/// The user's pinch over a grid: nil follows the fit scale; a grid with other columns goes back to it.
public struct TerminalZoom: Equatable, Sendable {
    public private(set) var zoom: CGFloat?
    private var cols: Int?

    public init() {}

    /// Remembers `cols`; a different value than the last sets the zoom back to nil (fit).
    public mutating func gridChanged(cols: Int) {
        if cols != self.cols { zoom = nil }
        self.cols = cols
    }

    /// Stores the pinch, kept between `fit` and `TerminalGeometry.maxZoom`.
    public mutating func pinch(to zoom: CGFloat, fit: CGFloat) {
        self.zoom = min(max(zoom, fit), TerminalGeometry.maxZoom)
    }

    /// The scale to draw at: the pinch (or fit), never below `fit` nor above `TerminalGeometry.maxZoom`.
    public func scale(fit: CGFloat) -> CGFloat {
        min(max(zoom ?? fit, fit), TerminalGeometry.maxZoom)
    }
}
