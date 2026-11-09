import Foundation
import XCTest
@testable import ShellXAppCore

final class TerminalColorsTests: XCTestCase {
    /// fg #d0d0d0, bg #101010, colors[i] = grey i, colors[2] = "#00ff00".
    private let palette: TerminalPalette = {
        var colors = (0..<256).map { String(format: "#%02x%02x%02x", $0, $0, $0) }
        colors[2] = "#00ff00"
        return TerminalPalette(fg: "#d0d0d0", bg: "#101010", colors: colors)
    }()

    func testDefaultStyleUsesThePalette() {
        let style = TerminalColors.resolve(.default, palette: palette)
        XCTAssertEqual(style.foreground, TerminalRGB(red: 0xd0, green: 0xd0, blue: 0xd0)); XCTAssertNil(style.background)
        XCTAssertTrue(style.drawsText); XCTAssertFalse(style.bold)
    }

    func testIndexedAndRGBColours() {
        let style = TerminalColors.resolve(TerminalCellStyle(fg: 2, bgRgb: "#336699"), palette: palette)
        XCTAssertEqual(style.foreground, TerminalRGB(red: 0, green: 255, blue: 0))
        XCTAssertEqual(style.background, TerminalRGB(red: 0x33, green: 0x66, blue: 0x99))
    }

    func testInverseSwapsEvenTheDefaults() {
        let style = TerminalColors.resolve(TerminalCellStyle(attrs: [.inverse]), palette: palette)
        XCTAssertEqual(style.foreground, TerminalRGB(red: 0x10, green: 0x10, blue: 0x10))
        XCTAssertEqual(style.background, TerminalRGB(red: 0xd0, green: 0xd0, blue: 0xd0))
    }

    func testFaintBlendsHalfwayToTheBackground() {
        let style = TerminalColors.resolve(TerminalCellStyle(fgRgb: "#ffffff", bgRgb: "#000000", attrs: [.faint]), palette: palette)
        XCTAssertEqual(style.foreground, TerminalRGB(red: 128, green: 128, blue: 128))
    }

    func testInvisibleBoldItalicUnderlineStrikeOverline() {
        let style = TerminalColors.resolve(
            TerminalCellStyle(attrs: [.invisible, .bold, .italic, .underline, .strike, .overline, .blink]), palette: palette)
        XCTAssertFalse(style.drawsText)
        XCTAssertTrue(style.bold && style.italic && style.underline && style.strike && style.overline)
    }

    func testBadColoursFallBack() {
        XCTAssertNil(TerminalColors.rgb("#12345")); XCTAssertEqual(TerminalColors.rgb("#AbCdEf"), TerminalRGB(red: 0xab, green: 0xcd, blue: 0xef))
        let broken = TerminalPalette(fg: "red", bg: "#101010", colors: palette.colors)
        XCTAssertEqual(TerminalColors.foreground(broken), TerminalRGB(red: 255, green: 255, blue: 255))
        XCTAssertEqual(TerminalColors.cursor(palette), TerminalColors.foreground(palette))
    }
}
