import Testing
import Foundation
@testable import ShellXBrand

@Suite struct ShellXBrandTests {
    @Test func paletteMatchesSpec() {
        #expect(ShellXPalette.bg.hexString == "#0b0716")
        #expect(ShellXPalette.panel.hexString == "#100b1d")
        #expect(ShellXPalette.raise.hexString == "#171128")
        #expect(ShellXPalette.line.hexString == "#211a37")
        #expect(ShellXPalette.border.hexString == "#2a2145")
        #expect(ShellXPalette.text.hexString == "#cdc7e0")
        #expect(ShellXPalette.textHi.hexString == "#e6e2f2")
        #expect(ShellXPalette.muted.hexString == "#8a83a6")
        #expect(ShellXPalette.primary.hexString == "#60a5fa")
        #expect(ShellXPalette.primaryText.hexString == "#93c5fd")
        #expect(ShellXPalette.running.hexString == "#e8c468")
        #expect(ShellXPalette.done.hexString == "#6fd49a")
        #expect(ShellXPalette.error.hexString == "#e88a8a")
        #expect(ShellXPalette.primarySoft.hexString == "#60a5fa" && ShellXPalette.primarySoft.alpha == 0.12)
        #expect(ShellXPalette.primaryLine.hexString == "#60a5fa" && ShellXPalette.primaryLine.alpha == 0.45)
    }

    @Test func opaqueTokensHaveFullAlpha() {
        #expect(ShellXPalette.bg.alpha == 1)
        #expect(ShellXPalette.primary.alpha == 1)
    }

    @Test func colorBridgesCarryComponents() {
        let c = ShellXColor(hex: 0x60a5fa, alpha: 0.5)
        #expect(c == ShellXColor(hex: 0x60a5fa, alpha: 0.5))
        #expect(c != ShellXColor(hex: 0x60a5fa))
        let ns = c.nsColor.usingColorSpace(.sRGB)
        #expect(ns != nil)
        #expect(abs((ns?.redComponent ?? 0) - 0x60 / 255.0) < 0.001)
        #expect(abs((ns?.alphaComponent ?? 0) - 0.5) < 0.001)
        _ = c.color
    }

    @Test func identity() {
        #expect(ShellXBrand.appName == "ShellX")
        #expect(ShellXBrand.cliName == "shellx")
        #expect(ShellXBrand.bundleID == "pro.shellx.desktop")
        #expect(ShellXBrand.teamID == "W4RF3W4VTZ")
        #expect(ShellXBrand.urlScheme == "shellx")
        #expect(ShellXBrand.configDirectoryName == "shellx")
        #expect(ShellXBrand.configFileName == "shellx.json")
        #expect(ShellXBrand.projectConfigDirectoryName == ".shellx")
        #expect(ShellXBrand.appSupportDirectoryName == "ShellX")
        #expect(ShellXBrand.socketBaseName == "shellx")
        #expect(ShellXBrand.hookMarker == "__shellx")
        #expect(ShellXBrand.utiPrefix == "pro.shellx")
        #expect(ShellXBrand.websiteURL.absoluteString == "https://shellx.pro")
        #expect(ShellXBrand.sourceCodeURL.absoluteString == "https://github.com/lephus/shellx")
        #expect(ShellXBrand.contactEmail == "phule9225@gmail.com")
        #expect(ShellXBrand.updateFeedURL.absoluteString == "https://download.shellx.pro/desktop/appcast.xml")
        #expect(ShellXFeatures.remoteMachines == false)
    }
}
