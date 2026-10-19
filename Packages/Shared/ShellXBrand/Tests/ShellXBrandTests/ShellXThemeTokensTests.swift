import AppKit
import CoreText
import Foundation
import SwiftUI
import Testing
@testable import ShellXBrand

/// ShellX look tokens beyond the palette: dark-only appearance, status
/// colors, the built-in terminal theme and the Space Grotesk display font
/// (spec §7.4).
@Suite struct ShellXThemeTokensTests {
    // MARK: Appearance

    @Test func appIsDarkOnly() {
        #expect(ShellXAppearance.forcedAppearanceName == .darkAqua)
        #expect(ShellXAppearance.forcedModeRawValue == "dark")
        #expect(ShellXAppearance.forcedAppearance?.name == .darkAqua)
    }

    // MARK: Status colors

    @Test func statusColorsFollowTheSpecTable() {
        #expect(ShellXStatus.needsYou.color == ShellXPalette.primary)
        #expect(ShellXStatus.running.color == ShellXPalette.running)
        #expect(ShellXStatus.done.color == ShellXPalette.done)
        #expect(ShellXStatus.error.color == ShellXPalette.error)
        #expect(ShellXStatus.idle.color == ShellXPalette.muted)
        #expect(ShellXStatus.needsYou.color.hexString == "#60a5fa")
        #expect(ShellXStatus.running.color.hexString == "#e8c468")
        #expect(ShellXStatus.done.color.hexString == "#6fd49a")
        #expect(ShellXStatus.error.color.hexString == "#e88a8a")
    }

    // MARK: Terminal theme

    @Test func terminalThemeUsesPalette() {
        #expect(ShellXTerminalTheme.background == ShellXPalette.bg)
        #expect(ShellXTerminalTheme.foreground == ShellXPalette.text)
        #expect(ShellXTerminalTheme.cursor == ShellXPalette.primary)
        #expect(ShellXTerminalTheme.cursorText == ShellXPalette.bg)
        #expect(ShellXTerminalTheme.selectionForeground == ShellXPalette.textHi)
        #expect(ShellXTerminalTheme.background.hexString == "#0b0716")
        #expect(ShellXTerminalTheme.cursor.hexString == "#60a5fa")
    }

    @Test func terminalThemeHasSixteenOpaqueAnsiColors() {
        let ansi = ShellXTerminalTheme.ansi
        #expect(ansi.count == 16)
        #expect(ansi.allSatisfy { $0.alpha == 1 })
        #expect(Set(ansi.map(\.hexString)).count == 16)
        // Normal hues reuse the status tokens so ls/git/prompt colors match
        // the chrome.
        #expect(ansi[1] == ShellXPalette.error)
        #expect(ansi[2] == ShellXPalette.done)
        #expect(ansi[3] == ShellXPalette.running)
        #expect(ansi[4] == ShellXPalette.primary)
        #expect(ansi[7] == ShellXPalette.text)
        #expect(ansi[12] == ShellXPalette.primaryText)
        #expect(ansi[15] == ShellXPalette.textHi)
        #expect(ansi.map(\.hexString) == [
            "#211a37", "#e88a8a", "#6fd49a", "#e8c468",
            "#60a5fa", "#c49af0", "#6fc8d9", "#cdc7e0",
            "#6e6790", "#f2a7a7", "#93e2b4", "#f2d68f",
            "#93c5fd", "#d9b8f7", "#96dbe7", "#e6e2f2",
        ])
    }

    @Test func terminalThemeSelectionAndDimTextStayReadable() {
        let bg = ShellXTerminalTheme.background
        // Selected text must read clearly over the selection fill.
        #expect(contrast(ShellXTerminalTheme.selectionForeground, ShellXTerminalTheme.selectionBackground) >= 7)
        // Body text and bright black (autosuggestions, comments) over bg.
        #expect(contrast(ShellXTerminalTheme.foreground, bg) >= 7)
        #expect(contrast(ShellXTerminalTheme.ansi[8], bg) >= 3)
        // Every colored entry (1-6, 9-14) reads as text on the background.
        for index in [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14] {
            #expect(contrast(ShellXTerminalTheme.ansi[index], bg) >= 4.5, "ansi \(index)")
        }
    }

    @Test func ghosttyConfigContentsCarryEveryThemeValue() {
        let lines = ShellXTerminalTheme.ghosttyConfigContents
            .split(separator: "\n")
            .map(String.init)
        #expect(lines.count == 22)
        for (index, color) in ShellXTerminalTheme.ansi.enumerated() {
            #expect(lines.contains("palette = \(index)=\(color.hexString)"))
        }
        #expect(lines.contains("background = #0b0716"))
        #expect(lines.contains("foreground = #cdc7e0"))
        #expect(lines.contains("cursor-color = #60a5fa"))
        #expect(lines.contains("cursor-text = #0b0716"))
        #expect(lines.contains("selection-background = \(ShellXTerminalTheme.selectionBackground.hexString)"))
        #expect(lines.contains("selection-foreground = #e6e2f2"))
        #expect(ShellXTerminalTheme.name == "ShellX")
    }

    // MARK: Display font

    @Test func displayFontFallsBackToSystemWhenSpaceGroteskIsMissing() {
        let font = ShellXFonts.display(size: 20, weight: .bold, isFamilyAvailable: { _ in false })
        #expect(font == Font.system(size: 20, weight: .bold))
    }

    @Test func displayFontUsesSpaceGroteskWhenAvailable() {
        var asked: [String] = []
        let font = ShellXFonts.display(size: 20, weight: .semibold, isFamilyAvailable: {
            asked.append($0)
            return true
        })
        #expect(asked == ["Space Grotesk"])
        #expect(font == Font.custom("Space Grotesk", size: 20).weight(.semibold))
        #expect(ShellXFonts.display(size: 14) == ShellXFonts.display(size: 14, weight: .bold))
    }

    /// The bundled file must register under the family name the code asks for.
    @Test func bundledSpaceGroteskRegistersUnderTheFamilyName() throws {
        let fontsDir = Self.repoRoot.appendingPathComponent("Resources/Fonts", isDirectory: true)
        let fontURL = fontsDir.appendingPathComponent("SpaceGrotesk[wght].ttf")
        #expect(FileManager.default.fileExists(atPath: fontURL.path))
        #expect(FileManager.default.fileExists(atPath: fontsDir.appendingPathComponent("OFL.txt").path))
        let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])
        let families = Set(descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
        })
        #expect(families == [ShellXFonts.familyName])
    }

    // MARK: Helpers

    private static var repoRoot: URL {
        // Tests/ShellXBrandTests/<file> -> package -> Shared -> Packages -> repo
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contrast(_ a: ShellXColor, _ b: ShellXColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func luminance(_ color: ShellXColor) -> Double {
        let ns = color.nsColor.usingColorSpace(.sRGB) ?? color.nsColor
        func lin(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(ns.redComponent) + 0.7152 * lin(ns.greenComponent) + 0.0722 * lin(ns.blueComponent)
    }
}
