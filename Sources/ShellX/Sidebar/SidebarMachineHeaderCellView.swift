import AppKit
import ShellXBrand

/// Pure-AppKit machine section header: icon, "MacBook Pro · this Mac",
/// online dot. Modelled on `SidebarGroupHeaderTableCellView` (manual layout,
/// subviews made once). The row height is fixed; the label truncates.
@MainActor
final class SidebarMachineHeaderCellView: NSTableCellView, ShellXSidebarHeaderCell {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarMachineHeaderCellView")

    private let iconImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let onlineDotView = NSView()
    private var header: SidebarMachineHeaderModel?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier
        wantsLayer = true

        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.contentTintColor = ShellXPalette.muted.nsColor
        addSubview(iconImageView)

        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.isSelectable = false
        addSubview(titleField)

        onlineDotView.wantsLayer = true
        onlineDotView.layer?.cornerRadius = ShellXSidebarHeaderMetrics.onlineDotSide / 2
        addSubview(onlineDotView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            needsLayout = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        header = nil
    }

    func configure(header row: ShellXSidebarHeaderRow) {
        guard case .machine(let header) = row else { return }
        guard header != self.header else { return }
        self.header = header

        iconImageView.image = ShellXSidebarIcon.image(
            named: header.coolicon,
            pointSize: ShellXSidebarHeaderMetrics.iconSide
        )

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let title = NSMutableAttributedString(
            string: header.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: ShellXPalette.textHi.nsColor,
                .paragraphStyle: truncating,
            ]
        )
        title.append(NSAttributedString(
            string: " \u{00B7} " + header.note,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: ShellXPalette.muted.nsColor,
                .paragraphStyle: truncating,
            ]
        ))
        titleField.attributedStringValue = title
        titleField.toolTip = header.title

        onlineDotView.layer?.backgroundColor = header.isOnline
            ? ShellXPalette.done.nsColor.cgColor
            : ShellXPalette.muted.nsColor.cgColor
        onlineDotView.setAccessibilityElement(true)
        onlineDotView.setAccessibilityRole(.image)
        onlineDotView.setAccessibilityLabel(
            header.isOnline
                ? String(localized: "sidebar.machine.online", defaultValue: "Online")
                : String(localized: "sidebar.machine.offline", defaultValue: "Offline")
        )
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let leading = SidebarWorkspaceListMetrics.rowOuterHorizontalPadding
            + SidebarWorkspaceListMetrics.rowContentHorizontalPadding
        let trailing = bounds.width - leading
        let midY = bounds.height / 2 + 2
        let iconSide = ShellXSidebarHeaderMetrics.iconSide
        let dotSide = ShellXSidebarHeaderMetrics.onlineDotSide
        iconImageView.frame = NSRect(x: leading, y: midY - iconSide / 2, width: iconSide, height: iconSide)

        let textX = iconImageView.frame.maxX + 8
        let available = max(0, trailing - textX - dotSide - 8)
        let textSize = titleField.attributedStringValue.size()
        let textWidth = min(ceil(textSize.width) + 4, available)
        titleField.frame = NSRect(
            x: textX,
            y: midY - ceil(textSize.height) / 2,
            width: textWidth,
            height: ceil(textSize.height)
        )
        onlineDotView.frame = NSRect(
            x: titleField.frame.maxX + 6,
            y: midY - dotSide / 2,
            width: dotSide,
            height: dotSide
        )
    }
}
