import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import CmuxFoundation
import ShellXBrand
import SwiftUI

/// The styles ShellX hands to Bonsplit's tab bars (spec §6.2).
///
/// The selected tab of the focused pane is the app accent at a low alpha behind a bold,
/// near-white title, with a 2 pt accent indicator on its bottom edge. The selected tab of any
/// other pane is a neutral wash with a violet-grey indicator, so a split tree shows one accent tab.
/// Only the accent follows the user's setting; every other color is a ``ShellXPalette`` token.
///
/// A tab bar over a light terminal theme gets no styles (ruling R6): the palette is made for dark
/// bars, so Bonsplit keeps drawing its default selected tab there.
///
/// A window has exactly one accent tab, so only a workspace's own split tree gets the selected
/// tab style. The Dock and the remote-tmux trees nested in a workspace have focused panes of
/// their own and keep Bonsplit's default selected tab.
///
/// The agent activity effects (spec §6.4) are the same on every dark tab bar, the Dock and the
/// nested trees included, and on the dark sidebar's rows; they never follow the accent.
///
/// ```swift
/// let styles = ShellXBonsplitStyles(accent: ShellXPalette.primary)
/// styles.selectedTabStyle.fillHex // "#60a5fa29"
/// styles.titleEffectStyle.flashHex // "#d6c4ff42"
/// ```
struct ShellXBonsplitStyles: Equatable {
    /// The accent and the alphas ShellX washes it with.
    private let tint: ShellXSelectionTint

    /// Creates the styles for an accent as a dark tab bar draws it.
    ///
    /// - Parameter accent: The accent color. Its alpha is ignored: each fill sets its own.
    init(accent: ShellXColor) {
        tint = ShellXSelectionTint(accent: accent)
    }

    /// Creates the styles for the app accent over a tab bar, or `nil` where the bar is light.
    ///
    /// The bar is light when black text reads better on it than white, the same choice Bonsplit
    /// makes for the bar's own text. The near-white title and the pale unfocused fill are only
    /// ever drawn where Bonsplit draws light text.
    ///
    /// - Parameters:
    ///   - accent: The app accent, read as the dark sidebar draws it.
    ///   - chromeBackground: The opaque color behind the tab bar, which is the terminal
    ///     background composited over the window.
    init?(accent: CmuxAccentColor, chromeBackground: NSColor) {
        guard WindowChromeColorResolver().readableColorScheme(for: chromeBackground) == .dark else {
            return nil
        }
        tint = ShellXSelectionTint(sidebarAccent: accent)
    }

    /// The styles for the accent the app draws now, which the sidebar selection also uses.
    ///
    /// - Parameter chromeBackground: The opaque color behind the tab bar.
    /// - Returns: The styles, or `nil` over a light bar.
    @MainActor
    static func current(overChromeBackground chromeBackground: NSColor) -> ShellXBonsplitStyles? {
        ShellXBonsplitStyles(
            accent: AppDelegate.shared?.accentColor ?? CmuxAccentColor(),
            chromeBackground: chromeBackground
        )
    }

    /// The selected tab, given to Bonsplit through `Appearance.selectedTabStyle`.
    var selectedTabStyle: SelectedTabStyle {
        SelectedTabStyle(
            fillHex: tint.tabFill(isWindowKey: true).hexStringWithAlpha,
            inactiveWindowFillHex: tint.tabFill(isWindowKey: false).hexStringWithAlpha,
            unfocusedPaneFillHex: ShellXPalette.textHi.withAlpha(0.07).hexStringWithAlpha,
            titleHex: ShellXPalette.selectionTitle.hexString,
            unfocusedPaneTitleHex: ShellXPalette.text.hexString,
            indicatorHex: tint.accent.hexString,
            unfocusedPaneIndicatorHex: ShellXPalette.unfocusedTabIndicator.hexString,
            indicatorThickness: 2,
            boldsSelectedTitle: true
        )
    }

    /// The agent activity effects, given to Bonsplit through `Appearance.titleEffectStyle`.
    var titleEffectStyle: TitleEffectStyle {
        Self.darkTitleEffectStyle
    }

    /// The agent activity effects for a tab bar or sidebar drawn in a color scheme.
    ///
    /// The effect colors are made for dark chrome, so a light tab bar or sidebar plays none.
    ///
    /// - Parameter colorScheme: The scheme the tab bar or sidebar is drawn in.
    /// - Returns: The effects, or `nil` for a light scheme.
    static func titleEffectStyle(for colorScheme: ColorScheme) -> TitleEffectStyle? {
        colorScheme == .dark ? darkTitleEffectStyle : nil
    }

    /// The effect colors from the palette. The flash keeps its alpha; the durations are
    /// Bonsplit's defaults, which are the spec's timing.
    private static let darkTitleEffectStyle = TitleEffectStyle(
        workingBaseHex: ShellXPalette.effectWorkingBase.hexString,
        workingHighlightHex: ShellXPalette.effectWorkingHighlight.hexString,
        glyphWorkingHex: ShellXPalette.running.hexString,
        flashHex: ShellXPalette.effectFlash.hexStringWithAlpha,
        highlightStopHexes: ShellXPalette.effectHighlightStops.map(\.hexString)
    )
}
