import AppKit
import Foundation
import Testing
@testable import ShellXBrand

/// The selected-session tint (spec §6.1, §6.2, §6.4): the accent composited
/// over `panel` for the sidebar, the accent at low alpha for the tab bar, and
/// the new selection and effect tokens. Contrast is pinned for the default
/// accent only (ruling R9).
@Suite struct ShellXSelectionTintTests {
    private let tint = ShellXSelectionTint(accent: ShellXPalette.primary)

    @Test func sidebarFillComposesAccentOverPanel() {
        let emphasized = tint.sidebarFill(isEmphasized: true)
        #expect(Self.channelsMatch(emphasized, "#222d4e"))
        #expect(emphasized.alpha == 1)
        // Spec §2: the selected row reads against the sidebar at 1.4:1 or more.
        #expect(Self.contrast(emphasized, ShellXPalette.panel) >= 1.4)

        let unemphasized = tint.sidebarFill(isEmphasized: false)
        #expect(Self.channelsMatch(unemphasized, "#1d2440"))
        #expect(unemphasized.alpha == 1)
        #expect(Self.channels(unemphasized).blue < Self.channels(emphasized).blue)
    }

    @Test func multiSelectionIsLighterThanSelection() {
        let multi = tint.multiSelectionFill(increaseContrast: false)
        let stronger = tint.multiSelectionFill(increaseContrast: true)
        let selected = tint.sidebarFill(isEmphasized: true)
        #expect(Self.channelsMatch(multi, "#181a33"))
        #expect(Self.channelsMatch(stronger, "#1e2745"))
        #expect(multi.alpha == 1 && stronger.alpha == 1)
        #expect(Self.contrast(multi, ShellXPalette.panel) < Self.contrast(selected, ShellXPalette.panel))
        #expect(Self.contrast(multi, ShellXPalette.panel) < Self.contrast(stronger, ShellXPalette.panel))
    }

    @Test func effectColorsReadOnSelectionAndPanel() {
        let colors = [ShellXPalette.effectWorkingBase] + ShellXPalette.effectHighlightStops
        let backgrounds = [ShellXPalette.panel, tint.sidebarFill(isEmphasized: true)]
        for color in colors {
            for background in backgrounds {
                #expect(
                    Self.contrast(color, background) >= 4.5,
                    "\(color.hexString) on \(background.hexString)"
                )
            }
        }
    }

    @Test func selectionTitleContrast() {
        let fill = tint.sidebarFill(isEmphasized: true)
        #expect(Self.contrast(ShellXPalette.selectionTitle, fill) >= 7)
        #expect(Self.contrast(ShellXPalette.selectionSecondary, fill) >= 4.5)
        #expect(Self.contrast(ShellXPalette.selectionTitle, tint.sidebarFill(isEmphasized: false)) >= 7)
    }

    @Test func tabFillIsTheAccentAtLowAlphaWithoutCompositing() {
        let key = tint.tabFill(isWindowKey: true)
        let inactive = tint.tabFill(isWindowKey: false)
        #expect(key.hexString == "#60a5fa")
        #expect(key.alpha == 0.16)
        #expect(key.hexStringWithAlpha == "#60a5fa29")
        #expect(inactive.hexString == "#60a5fa")
        #expect(inactive.alpha == 0.12)
        #expect(inactive.hexStringWithAlpha == "#60a5fa1f")

        let custom = ShellXSelectionTint(accent: ShellXColor(hex: 0xff8800)).tabFill(isWindowKey: true)
        #expect(custom.hexStringWithAlpha == "#ff880029")
    }

    @Test func customAccentKeepsItsHueInTheSidebarFill() {
        let orange = ShellXSelectionTint(accent: ShellXColor(hex: 0xff8800))
        // 22% of #ff8800 over #100b1d: (68.6, 38.5, 22.6) rounds to #452717.
        #expect(Self.channelsMatch(orange.sidebarFill(isEmphasized: true), "#452717"))
        #expect(orange != tint)
        #expect(orange == ShellXSelectionTint(accent: ShellXColor(hex: 0xff8800)))
    }

    @Test func selectionAndEffectTokensMatchTheSpec() {
        #expect(ShellXPalette.selectionTitle.hexString == "#f1f5ff")
        #expect(ShellXPalette.selectionSecondary.hexString == "#b4c6e6")
        #expect(ShellXPalette.rowHover.hexString == "#1b1530")
        #expect(ShellXPalette.unfocusedTabIndicator.hexString == "#5b5478")
        #expect(ShellXPalette.selectionPillBacking.hexString == "#0b0716")
        #expect(ShellXPalette.selectionPillBacking.alpha == 0.55)
        #expect(ShellXPalette.selectionWaitingRing.hexString == "#93c5fd")
        #expect(ShellXPalette.selectionWaitingRing.alpha == 0.8)
        #expect(ShellXPalette.effectWorkingBase.hexString == "#b39550")
        #expect(ShellXPalette.effectWorkingHighlight.hexString == "#fff3cf")
        #expect(ShellXPalette.effectFlash.hexString == "#d6c4ff")
        #expect(ShellXPalette.effectFlash.alpha == 0.26)
        #expect(ShellXPalette.effectFlash.hexStringWithAlpha == "#d6c4ff42")
        #expect(ShellXPalette.effectHighlightStops.map(\.hexString) == [
            "#f4a7c0", "#f2c879", "#8fd9a8", "#7cc8e8", "#9fb0f5", "#c9a7f2", "#f4a7c0"
        ])
        #expect(ShellXPalette.effectHighlightStops.allSatisfy { $0.alpha == 1 })
    }

    @Test func colorHelpersConvertAndComposite() throws {
        #expect(ShellXColor(nsColor: ShellXPalette.primary.nsColor) == ShellXPalette.primary)
        let translucent = ShellXColor(nsColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5))
        #expect(translucent.hexString == "#ff0000")
        #expect(translucent.alpha == 0.5)
        // Non-sRGB colors are converted before they are read.
        #expect(ShellXColor(nsColor: NSColor(calibratedWhite: 1, alpha: 1)).hexString == "#ffffff")
        #expect(ShellXColor(nsColor: NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)).hexString == "#000000")

        #expect(ShellXPalette.primary.withAlpha(0.3) == ShellXColor(hex: 0x60a5fa, alpha: 0.3))
        #expect(ShellXPalette.primary.withAlpha(0.3).withAlpha(1) == ShellXPalette.primary)

        let half = ShellXColor(hex: 0xffffff, alpha: 0.5).composited(over: ShellXColor(hex: 0x000000))
        #expect(half.hexString == "#808080")
        #expect(half.alpha == 1)
        // An opaque color covers the base completely; the base's alpha is ignored.
        #expect(ShellXPalette.primary.composited(over: ShellXColor(hex: 0x000000, alpha: 0.2)) == ShellXPalette.primary)
        #expect(ShellXColor(hex: 0x123456, alpha: 0).composited(over: ShellXPalette.panel) == ShellXPalette.panel)

        #expect(ShellXPalette.primary.hexStringWithAlpha == "#60a5faff")
        #expect(ShellXColor(hex: 0x0b0716, alpha: 0).hexStringWithAlpha == "#0b071600")
    }

    // MARK: Helpers

    private static func channels(_ color: ShellXColor) -> (red: Int, green: Int, blue: Int) {
        let value = Int(color.hexString.dropFirst(), radix: 16) ?? 0
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    /// Each channel within one step of `hex`, so rounding choices don't matter.
    private static func channelsMatch(_ color: ShellXColor, _ hex: String) -> Bool {
        let actual = channels(color)
        let expected = channels(ShellXColor(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0))
        return abs(actual.red - expected.red) <= 1
            && abs(actual.green - expected.green) <= 1
            && abs(actual.blue - expected.blue) <= 1
    }

    private static func contrast(_ a: ShellXColor, _ b: ShellXColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ color: ShellXColor) -> Double {
        let ns = color.nsColor.usingColorSpace(.sRGB) ?? color.nsColor
        func lin(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(ns.redComponent) + 0.7152 * lin(ns.greenComponent) + 0.0722 * lin(ns.blueComponent)
    }
}
