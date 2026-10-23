import AppKit
import CmuxFoundation
import CmuxSettings
import ShellXBrand
import SwiftUI

extension ShellXSelectionTint {
    /// The tint for the app accent, read as the dark sidebar draws it.
    init(sidebarAccent accent: CmuxAccentColor) {
        self.init(accent: ShellXColor(nsColor: accent.nsColor(for: .dark)))
    }

    /// ShellX's selection tint for a sidebar (spec §6.1), or nil where the
    /// sidebar keeps the paint it had before the tint: a light sidebar, a
    /// configured selection color, the solid-fill indicator style, or the
    /// subtle selection. Every explicit choice of the user wins.
    init?(
        sidebarColorScheme colorScheme: ColorScheme,
        sidebarSelectionColorHex: String?,
        activeTabIndicatorStyle: WorkspaceIndicatorStyle,
        subtleSelection: Bool,
        accent: CmuxAccentColor
    ) {
        guard colorScheme == .dark,
              activeTabIndicatorStyle == .leftRail,
              !subtleSelection,
              sidebarSelectionColorHex.flatMap({ NSColor(hex: $0) }) == nil else {
            return nil
        }
        self.init(sidebarAccent: accent)
    }
}
