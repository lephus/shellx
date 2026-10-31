import AppKit
import Testing
@testable import ShellXBrand

/// Sidebar header text keeps ShellX's tokens on a dark sidebar and takes the
/// system label colors on a light one (a light terminal theme), so the
/// brand name, section label and machine names stay readable on either.
@Suite struct ShellXSidebarTextTests {
    @Test func darkSidebarDrawsShellXTokens() {
        #expect(resolved(ShellXSidebarText.title, in: .darkAqua) == components(ShellXPalette.textHi.nsColor))
        #expect(resolved(ShellXSidebarText.muted, in: .darkAqua) == components(ShellXPalette.muted.nsColor))
        #expect(resolved(ShellXSidebarText.link, in: .darkAqua) == components(ShellXPalette.primaryText.nsColor))
    }

    @Test func lightSidebarDrawsSystemLabelColors() {
        #expect(resolved(ShellXSidebarText.title, in: .aqua) == resolved(.labelColor, in: .aqua))
        #expect(resolved(ShellXSidebarText.muted, in: .aqua) == resolved(.secondaryLabelColor, in: .aqua))
        #expect(resolved(ShellXSidebarText.link, in: .aqua) == resolved(.linkColor, in: .aqua))
    }

    @Test func lightSidebarTextIsDarkEnoughToRead() {
        for color in [ShellXSidebarText.title, ShellXSidebarText.link] {
            let rgba = resolved(color, in: .aqua)
            let luminance = 0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2]
            #expect(luminance < 0.5)
        }
    }

    /// sRGB components rounded to 8 bits, so equal colors compare equal.
    private func resolved(_ color: NSColor, in name: NSAppearance.Name) -> [Double] {
        var result: [Double] = []
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            result = components(color)
        }
        return result
    }

    private func components(_ color: NSColor) -> [Double] {
        guard let srgb = color.usingColorSpace(.sRGB) else { return [] }
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
            .map { (Double($0) * 255).rounded() / 255 }
    }
}
