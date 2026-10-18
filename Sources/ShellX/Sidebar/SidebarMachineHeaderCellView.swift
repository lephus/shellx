import AppKit
import ShellXBrand

/// Pure-AppKit machine section header: icon, "MacBook Pro · this Mac",
/// online dot. Modelled on `SidebarGroupHeaderTableCellView` (manual layout,
/// subviews made once). The row height is fixed; the label truncates.
/// Remote machines add a trailing action (a "Request access" button or a
/// muted status) and render at half opacity while offline.
@MainActor
final class SidebarMachineHeaderCellView: NSTableCellView, ShellXSidebarHeaderCell {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarMachineHeaderCellView")

    private let iconImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let onlineDotView = NSView()
    private let actionButton = ShellXSidebarActionButton()
    private let actionField = NSTextField(labelWithString: "")
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

        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        actionButton.isHidden = true
        addSubview(actionButton)

        actionField.lineBreakMode = .byTruncatingTail
        actionField.maximumNumberOfLines = 1
        actionField.cell?.truncatesLastVisibleLine = true
        actionField.isSelectable = false
        actionField.isHidden = true
        addSubview(actionField)
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
        if !header.note.isEmpty {
            title.append(NSAttributedString(
                string: " \u{00B7} " + header.note,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: ShellXPalette.muted.nsColor,
                    .paragraphStyle: truncating,
                ]
            ))
        }
        titleField.attributedStringValue = title
        titleField.toolTip = header.title
        // Offline remote machines: the whole header at half opacity.
        alphaValue = header.isDimmed ? 0.5 : 1
        configureAction(header.action, truncating: truncating)

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

    private func configureAction(_ action: SidebarMachineHeaderAction?, truncating: NSParagraphStyle) {
        actionButton.isHidden = true
        actionField.isHidden = true
        switch action {
        case .requestAccess:
            let title = String(localized: "remote.machine.requestAccess", defaultValue: "Request access")
            actionButton.applyTitle(title)
            actionButton.toolTip = title
            actionButton.setAccessibilityLabel(title)
            actionButton.isHidden = false
        case .waiting(let code):
            showActionText(
                String(format: String(localized: "remote.machine.waiting", defaultValue: "waiting · %@"), code),
                truncating: truncating
            )
        case .connecting:
            showActionText(
                String(localized: "remote.machine.connecting", defaultValue: "connecting…"),
                truncating: truncating
            )
        case .reconnecting:
            showActionText(
                String(localized: "remote.machine.reconnecting", defaultValue: "reconnecting…"),
                truncating: truncating
            )
        case .open, nil:
            break
        }
    }

    private func showActionText(_ text: String, truncating: NSParagraphStyle) {
        actionField.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: ShellXPalette.muted.nsColor,
                .paragraphStyle: truncating,
            ]
        )
        actionField.toolTip = text
        actionField.isHidden = false
    }

    @objc private func actionButtonClicked() {
        guard let header, case .remote(let machineID) = header.key, header.action == .requestAccess else { return }
        ShellXRemoteUIActions.requestAccess(to: machineID)
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

        // Trailing action: at most 45% of the row so the machine name keeps room.
        let maxActionWidth = max(0, (trailing - leading) * 0.45)
        var actionMinX = trailing
        if !actionButton.isHidden {
            let buttonHeight = ShellXSidebarHeaderMetrics.actionButtonHeight
            let width = min(actionButton.fittingWidth, maxActionWidth)
            actionButton.frame = NSRect(x: trailing - width, y: midY - buttonHeight / 2, width: width, height: buttonHeight)
            actionMinX = actionButton.frame.minX - 8
        } else if !actionField.isHidden {
            let size = actionField.attributedStringValue.size()
            let width = min(ceil(size.width) + 4, maxActionWidth)
            actionField.frame = NSRect(
                x: trailing - width,
                y: midY - ceil(size.height) / 2,
                width: width,
                height: ceil(size.height)
            )
            actionMinX = actionField.frame.minX - 8
        }

        let textX = iconImageView.frame.maxX + 8
        let available = max(0, actionMinX - textX - dotSide - 8)
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

/// The small primary button on a remote machine header ("Request access"):
/// primarySoft fill, 1 px primaryLine border, primaryText. No gradient.
@MainActor
final class ShellXSidebarActionButton: NSButton {
    private static let horizontalPadding: CGFloat = 7

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
        imagePosition = .noImage
        setButtonType(.momentaryPushIn)
        cell?.lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTitle(_ text: String) {
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        truncating.alignment = .center
        attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: ShellXPalette.primaryText.nsColor,
                .paragraphStyle: truncating,
            ]
        )
        needsDisplay = true
    }

    var fittingWidth: CGFloat {
        ceil(attributedTitle.size().width) + 2 * Self.horizontalPadding
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        ShellXPalette.primarySoft.nsColor.setFill()
        path.fill()
        ShellXPalette.primaryLine.nsColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        super.draw(dirtyRect)
    }
}
