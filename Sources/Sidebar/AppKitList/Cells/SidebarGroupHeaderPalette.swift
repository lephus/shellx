import AppKit
import ShellXBrand
import SwiftUI

/// Selection colors for one pure-AppKit group header row.
///
/// A header whose anchor workspace is selected stands in for that
/// workspace's row (an anchor has no row of its own). In ShellX's dark
/// sidebar it paints the same tinted fill and `selection-title` name as a
/// selected workspace row (spec §6.1, ruling R8), without the name effect;
/// explicit selection settings keep the neutral label wash. A header in a
/// multi-selection paints the row multi-selection style precomputed into its
/// model.
@MainActor
struct SidebarGroupHeaderPalette {
    let model: SidebarGroupHeaderRowModel
    /// Whether the app is active and the header's window is key or main.
    var isSelectionEmphasized: Bool = true

    private var colorScheme: ColorScheme { model.colorSchemeIsDark ? .dark : .light }

    /// Whether the header paints ShellX's tinted selection, which follows
    /// window activation.
    var usesShellXSelection: Bool {
        model.isAnchorActive && model.anchorActiveSelectionTint != nil
    }

    /// Fill behind the header for its model state.
    var background: NSColor {
        if model.isAnchorActive { return anchorActiveBackground }
        if model.isMultiSelected { return multiSelectionBackground }
        return .clear
    }

    /// Fill while the anchor workspace is selected, also painted
    /// optimistically on press.
    var anchorActiveBackground: NSColor {
        if let tint = model.anchorActiveSelectionTint {
            return tint.sidebarFill(isEmphasized: isSelectionEmphasized).nsColor
        }
        return SidebarAppearanceColorResolver().resolvedColor(.labelColor, for: colorScheme, opacity: 0.08)
    }

    /// Dim membership tint of a header in a multi-selection.
    var multiSelectionBackground: NSColor {
        let style = model.multiSelectionBackgroundStyle
        guard let color = style.color else { return .clear }
        return color.withAlphaComponent(color.alphaComponent * style.opacity)
    }

    /// Group name color for the model state.
    var nameColor: NSColor {
        model.isAnchorActive ? anchorActiveNameColor : unselectedNameColor
    }

    /// Group name color while the anchor workspace is selected.
    var anchorActiveNameColor: NSColor {
        if model.anchorActiveSelectionTint != nil {
            return ShellXPalette.selectionTitle.nsColor
        }
        return SidebarAppearanceColorResolver().resolvedColor(.labelColor, for: colorScheme)
    }

    /// Group name color while the anchor workspace is not selected.
    var unselectedNameColor: NSColor {
        SidebarAppearanceColorResolver().resolvedColor(.labelColor, for: colorScheme, opacity: 0.9)
    }
}
