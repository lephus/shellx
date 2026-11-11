import SwiftUI
import UIKit

/// One line of the sign-in typewriter in SwiftUI: its first letters and, after them, the cursor (`TypedLineView`).
/// It takes the width it is offered and the height of the tallest of `lines`, two rows at least, in the taglines'
/// text style at the environment's type size, weight and appearance.
struct TypedLine: UIViewRepresentable {
    /// Every line the view may show: it is as high as the tallest needs.
    let lines: [String]
    /// The line shown.
    let line: String
    /// Its letters typed so far.
    let typed: String
    /// Whether the cursor shows after them.
    let cursorIsOn: Bool

    func makeUIView(context: Context) -> TypedLineView {
        TypedLineView()
    }

    func updateUIView(_ view: TypedLineView, context: Context) {
        let environment = context.environment
        view.show(
            TypedLineView.Content(lines: lines, line: line, typed: typed, cursorIsOn: cursorIsOn),
            font: TypedLineView.font(environment.dynamicTypeSize, bold: environment.legibilityWeight == .bold),
            dark: environment.colorScheme == .dark)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TypedLineView, context: Context) -> CGSize? {
        uiView.fittingSize(width: proposal.width)
    }
}

/// Draws one line of the typewriter: the letters typed so far and the cursor after them.
///
/// The letters and the cursor come out of one layout. TextKit lays out the whole line once for the view's width;
/// a frame then draws the glyphs of the typed letters and a block where the next letter will be (after the last
/// letter once the line is whole). So a word never moves while its line is typed, and the cursor cannot part from
/// the letters, wherever the line breaks. (Two SwiftUI texts over each other, one for the letters and one for the
/// cursor, each broke the line on its own, and not alike where iOS takes a word down to keep the last one company.)
///
/// The line is laid out in the view's width less the cursor's, so the cursor after the last letter of a full row
/// is still inside the view. The cursor is a block as high as a row; it takes no room in the line.
final class TypedLineView: UIView {
    /// What the view shows.
    struct Content: Equatable {
        /// Every line the view may show: it is as high as the tallest needs.
        var lines: [String] = []
        /// The line shown.
        var line = ""
        /// Its letters typed so far: the cursor stands after as many letters of `line`.
        var typed = ""
        /// Whether the cursor shows.
        var cursorIsOn = false
    }

    /// The taglines' text style.
    static let textStyle = UIFont.TextStyle.title3
    /// The rows the view always keeps room for.
    static let rows = 2
    /// The cursor's width as a part of the font's size: a block about as wide as a terminal's "▍".
    static let cursorShare: CGFloat = 0.22

    private(set) var content = Content()
    private(set) var font = UIFont.preferredFont(forTextStyle: TypedLineView.textStyle)
    private var textColor = UIColor.label
    private var cursorColor = UIColor.systemGreen

    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    /// The last size worked out, and the width it was for.
    private var fitted: (width: CGFloat, size: CGSize)?
    /// The height of one row in `font`, once measured.
    private var row: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// The taglines' font at `size`, in its bold weight when the user asks for bold text.
    static func font(_ size: DynamicTypeSize, bold: Bool = false) -> UIFont {
        let traits = UITraitCollection { traits in
            traits.preferredContentSizeCategory = UIContentSizeCategory(size)
            traits.legibilityWeight = bold ? .bold : .regular
        }
        return UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits)
    }

    /// Shows `content` in `font`, in the colours of the light or the dark appearance: the letters in the label
    /// colour, the cursor in the theme's green.
    func show(_ content: Content, font: UIFont, dark: Bool) {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let textColor = UIColor.label.resolvedColor(with: traits)
        let cursorColor = (UIColor(named: "StatusDone") ?? .systemGreen).resolvedColor(with: traits)
        let restyled = font != self.font || textColor != self.textColor
        guard restyled || content != self.content || cursorColor != self.cursorColor else { return }
        let relaid = restyled || content.line != self.content.line
        if font != self.font || content.lines != self.content.lines {
            fitted = nil
            invalidateIntrinsicContentSize()
        }
        if font != self.font { row = nil }
        self.content = content
        self.font = font
        self.textColor = textColor
        self.cursorColor = cursorColor
        if relaid { storage.setAttributedString(NSAttributedString(string: content.line, attributes: attributes)) }
        setNeedsDisplay()
    }

    /// The cursor's width.
    var cursorWidth: CGFloat { max(2, (font.pointSize * Self.cursorShare).rounded()) }

    /// The height of one row, as TextKit lays it out (it is a little more than the font's own line height).
    var rowHeight: CGFloat {
        if let row { return row }
        let height = Self.measure(" ", attributes: attributes, width: .greatestFiniteMagnitude).height
        row = height
        return height
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        // As a label breaks lines: a last word is not left alone on its row when the one before can join it.
        paragraph.lineBreakStrategy = .standard
        return [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
    }

    /// The view's size when it is offered `width`: that width, and the height of the tallest line in it, `rows`
    /// rows at least. Offered no width: each line on one row.
    func fittingSize(width: CGFloat?) -> CGSize {
        let least = CGFloat(Self.rows) * rowHeight
        guard let width, width.isFinite, width > 0 else {
            let widest = content.lines.map { Self.measure($0, attributes: attributes, width: .greatestFiniteMagnitude).width }.max() ?? 0
            return CGSize(width: (widest + cursorWidth).rounded(.up), height: least.rounded(.up))
        }
        if let fitted, fitted.width == width { return fitted.size }
        let tallest = content.lines.map { Self.measure($0, attributes: attributes, width: room(in: width)).height }.max() ?? 0
        let size = CGSize(width: width, height: max(least, tallest).rounded(.up))
        fitted = (width, size)
        return size
    }

    /// Where the cursor stands in a view `width` wide: at the place of the next letter, which is the start of the
    /// next row once a row is full, and after the last letter of a whole line. With no line, at the start.
    func cursorRect(in width: CGFloat) -> CGRect {
        layOut(in: width)
        let length = storage.length
        let glyphs = layoutManager.numberOfGlyphs
        guard length > 0, glyphs > 0 else { return CGRect(x: 0, y: 0, width: cursorWidth, height: rowHeight) }
        let typed = typedLength
        let glyph = typed < length ? layoutManager.glyphIndexForCharacter(at: typed) : glyphs - 1
        let row = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        return CGRect(x: typed < length ? box.minX : box.maxX, y: row.minY, width: cursorWidth, height: row.height)
    }

    /// The rows the line takes in a view `width` wide, as the ranges of its UTF-16 units.
    func rowRanges(in width: CGFloat) -> [NSRange] {
        layOut(in: width)
        var ranges: [NSRange] = []
        var glyph = 0
        while glyph < layoutManager.numberOfGlyphs {
            var row = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &row)
            ranges.append(layoutManager.characterRange(forGlyphRange: row, actualGlyphRange: nil))
            glyph = NSMaxRange(row)
        }
        return ranges
    }

    override func draw(_ rect: CGRect) {
        layOut(in: bounds.width)
        let typed = typedLength
        if typed > 0 {
            let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: typed), actualCharacterRange: nil)
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        }
        guard content.cursorIsOn else { return }
        // On whole pixels, so the block has hard edges wherever the letter before it ends.
        let scale = max(1, contentScaleFactor)
        let cursor = cursorRect(in: bounds.width)
        let left = (cursor.minX * scale).rounded() / scale
        let top = (cursor.minY * scale).rounded() / scale
        let bottom = (cursor.maxY * scale).rounded() / scale
        cursorColor.setFill()
        UIBezierPath(rect: CGRect(x: left, y: top, width: cursor.width, height: bottom - top)).fill()
    }

    /// How many UTF-16 units of the line are typed.
    private var typedLength: Int { min((content.typed as NSString).length, storage.length) }

    /// The room the line has in a view `width` wide: the cursor's width stays free at the right.
    private func room(in width: CGFloat) -> CGFloat { max(1, width - cursorWidth) }

    private func layOut(in width: CGFloat) {
        let size = CGSize(width: room(in: width), height: .greatestFiniteMagnitude)
        if container.size != size { container.size = size }
        layoutManager.ensureLayout(for: container)
    }

    /// The size `text` takes in `width`.
    private static func measure(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGSize {
        let storage = NSTextStorage(string: text, attributes: attributes)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).size
    }
}
