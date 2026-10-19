import AppKit
import ShellXBrand

/// Direct-draw status capsule ("waiting", "running", "done", "error"): the
/// status color at 12% as fill, the status color as text. No border,
/// gradient or shadow.
@MainActor
final class SidebarStatusPillView: NSView {
    private static let horizontalPadding: CGFloat = 6
    private static let baseFontSize: CGFloat = 9.5
    private static let baseHeight: CGFloat = 15

    private(set) var pill: SidebarStatusPill?
    private var fontScale: CGFloat = 1

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Hides the view for a nil pill. Returns whether anything changed.
    @discardableResult
    func configure(_ pill: SidebarStatusPill?, fontScale: CGFloat) -> Bool {
        let scale = max(0.5, fontScale)
        guard pill != self.pill || scale != self.fontScale else { return false }
        self.pill = pill
        self.fontScale = scale
        isHidden = pill == nil
        setAccessibilityLabel(pill?.title)
        needsDisplay = true
        return true
    }

    /// Shows the pill for a row's compact status glyph kind (none for nil).
    @discardableResult
    func configure(glyphKind: SidebarCompactStatusGlyph.Kind?, fontScale: CGFloat) -> Bool {
        configure(glyphKind.flatMap { SidebarStatusPill.from($0) }, fontScale: fontScale)
    }

    /// Size for the current pill; zero when there is none.
    var preferredSize: NSSize {
        guard let pill else { return .zero }
        let textSize = Self.attributedTitle(pill, fontScale: fontScale).size()
        return NSSize(
            width: ceil(textSize.width) + Self.horizontalPadding * 2 * fontScale,
            height: ceil(Self.baseHeight * fontScale)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let pill else { return }
        let radius = bounds.height / 2
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        pill.color.nsColor.withAlphaComponent(CGFloat(SidebarStatusPill.fillAlpha)).setFill()
        path.fill()
        if pill == .waiting {
            // Waiting for you = primary + ring: a 1 px primaryLine stroke inside the bounds.
            let ringRect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let ringRadius = ringRect.height / 2
            let ring = NSBezierPath(roundedRect: ringRect, xRadius: ringRadius, yRadius: ringRadius)
            ring.lineWidth = 1
            ShellXPalette.primaryLine.nsColor.setStroke()
            ring.stroke()
        }
        let title = Self.attributedTitle(pill, fontScale: fontScale)
        let textSize = title.size()
        title.draw(at: NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2
        ))
    }

    private static func attributedTitle(_ pill: SidebarStatusPill, fontScale: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: pill.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: baseFontSize * fontScale, weight: .medium),
                .foregroundColor: pill.textColor.nsColor,
            ]
        )
    }
}
