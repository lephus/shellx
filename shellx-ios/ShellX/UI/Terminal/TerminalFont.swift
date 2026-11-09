import CoreText
import UIKit

/// SF Mono at `size` (12 pt): regular, bold, italic and bold italic (italic falls back to the upright face when the
/// system has none), and the cell they make. CTFonts are immutable, hence @unchecked Sendable.
///
/// The terminal keeps this fixed size rather than following Dynamic Type: the Mac's grid has a fixed number of columns,
/// and a pinch zooms the drawing instead (`TerminalZoom`).
struct TerminalFont: @unchecked Sendable {
    static let size: CGFloat = 12
    static let standard = TerminalFont(size: size)

    /// width: the advance of "0" in the regular face; height: ceil(ascent + descent + leading).
    let cell: CGSize
    /// From a cell's top to its baseline: ascent plus half the leading.
    let baseline: CGFloat
    /// Below the baseline (CTFontGetUnderlinePosition, made positive downward).
    let underlineOffset: CGFloat
    /// CTFontGetUnderlineThickness, at least 1.
    let lineThickness: CGFloat

    private let regular: CTFont
    private let bold: CTFont
    private let italic: CTFont
    private let boldItalic: CTFont

    init(size: CGFloat) {
        let regular = UIFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
        let bold = UIFont.monospacedSystemFont(ofSize: size, weight: .bold) as CTFont
        self.regular = regular
        self.bold = bold
        italic = CTFontCreateCopyWithSymbolicTraits(regular, 0, nil, .traitItalic, .traitItalic) ?? regular
        boldItalic = CTFontCreateCopyWithSymbolicTraits(bold, 0, nil, .traitItalic, .traitItalic) ?? bold

        var character: UniChar = 0x30   // "0"
        var glyph: CGGlyph = 0
        var advance = CGSize.zero
        if CTFontGetGlyphsForCharacters(regular, &character, &glyph, 1) {
            CTFontGetAdvancesForGlyphs(regular, .horizontal, &glyph, &advance, 1)
        }
        let ascent = CTFontGetAscent(regular)
        let descent = CTFontGetDescent(regular)
        let leading = CTFontGetLeading(regular)
        cell = CGSize(width: advance.width > 0 ? advance.width : size * 0.6, height: ceil(ascent + descent + leading))
        baseline = ascent + leading / 2
        underlineOffset = -CTFontGetUnderlinePosition(regular)
        lineThickness = max(1, CTFontGetUnderlineThickness(regular))
    }

    func font(bold isBold: Bool, italic isItalic: Bool) -> CTFont {
        switch (isBold, isItalic) {
        case (false, false): return regular
        case (true, false): return bold
        case (false, true): return italic
        case (true, true): return boldItalic
        }
    }
}
