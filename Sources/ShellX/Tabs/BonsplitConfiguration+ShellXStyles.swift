import Bonsplit

/// ShellX's tab styles on a Bonsplit appearance: the selected tab (spec §6.2) and the agent
/// activity effects (spec §6.4).
///
/// A workspace's own split tree takes both from one ``ShellXBonsplitStyles``, which is `nil`
/// over a light tab bar; `nil` gives both back to Bonsplit's defaults, so a light bar looks as
/// it does upstream and plays no effects.
///
/// ```swift
/// var appearance = BonsplitConfiguration.Appearance.default
/// appearance.applyShellXStyles(ShellXBonsplitStyles(accent: ShellXPalette.primary))
/// appearance.titleEffectStyle?.workingBaseHex // "#b39550"
/// appearance.applyShellXStyles(nil)
/// appearance.titleEffectStyle // nil
/// ```
extension BonsplitConfiguration.Appearance {
    /// Whether the appearance already carries the styles, so applying them changes nothing.
    ///
    /// - Parameter styles: The styles for a dark bar, or `nil` for a light one.
    func carriesShellXStyles(_ styles: ShellXBonsplitStyles?) -> Bool {
        selectedTabStyle == styles?.selectedTabStyle
            && titleEffectStyle == styles?.titleEffectStyle
    }

    /// Sets the selected tab and the agent activity effects from the styles.
    ///
    /// - Parameter styles: The styles for a dark bar, or `nil` for a light one, which clears both.
    mutating func applyShellXStyles(_ styles: ShellXBonsplitStyles?) {
        selectedTabStyle = styles?.selectedTabStyle
        titleEffectStyle = styles?.titleEffectStyle
    }

    /// A copy of the appearance with the styles applied.
    ///
    /// - Parameter styles: The styles for a dark bar, or `nil` for a light one.
    func applyingShellXStyles(_ styles: ShellXBonsplitStyles?) -> Self {
        var appearance = self
        appearance.applyShellXStyles(styles)
        return appearance
    }
}
