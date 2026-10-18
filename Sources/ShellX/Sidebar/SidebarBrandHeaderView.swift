import AppKit
import ShellXBrand

/// First sidebar row: the ShellX logo and name, then the "YOUR MACHINES"
/// section label with an Add_Plus button that adds a machine over SSH.
@MainActor
final class SidebarBrandHeaderCellView: NSTableCellView, ShellXSidebarHeaderCell {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarBrandHeaderCellView")

    private let logoImageView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let sectionField = NSTextField(labelWithString: "")
    private let addButton = SidebarHeaderGlyphButton()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier
        wantsLayer = true

        logoImageView.imageScaling = .scaleProportionallyUpOrDown
        // ShellX: swap for ShellXIcon/ShellXFonts/ShellXLogo after W1 Tasks 7-9 merge
        logoImageView.image = NSApp.applicationIconImage
        addSubview(logoImageView)

        nameField.stringValue = ShellXBrand.appName
        // ShellX: swap for ShellXIcon/ShellXFonts/ShellXLogo after W1 Tasks 7-9 merge
        nameField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        nameField.textColor = ShellXPalette.textHi.nsColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.maximumNumberOfLines = 1
        nameField.isSelectable = false
        addSubview(nameField)

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        sectionField.attributedStringValue = NSAttributedString(
            // Section labels render uppercase in every locale ("MÁY CỦA BẠN").
            string: String(localized: "sidebar.machines.title", defaultValue: "YOUR MACHINES")
                .uppercased(with: .current),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: ShellXPalette.muted.nsColor,
                .kern: 0.8,
                .paragraphStyle: truncating,
            ]
        )
        sectionField.lineBreakMode = .byTruncatingTail
        sectionField.maximumNumberOfLines = 1
        sectionField.cell?.truncatesLastVisibleLine = true
        sectionField.isSelectable = false
        addSubview(sectionField)

        let addTitle = String(localized: "sidebar.machines.add.ssh", defaultValue: "Add a machine over SSH…")
        // ShellX: swap for ShellXIcon/ShellXFonts/ShellXLogo after W1 Tasks 7-9 merge
        addButton.glyphImage = ShellXSidebarIcon.image(named: "Add_Plus", pointSize: 12)
        addButton.contentTintColor = ShellXPalette.muted.nsColor
        addButton.toolTip = addTitle
        addButton.setAccessibilityLabel(addTitle)
        addButton.onClick = {
            ShellXAddMachinePrompt.present()
        }
        addButton.setRevealed(true)
        addSubview(addButton)
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

    func configure(header: ShellXSidebarHeaderRow) {
        // Static content; the logo follows the live app icon.
        logoImageView.image = NSApp.applicationIconImage
    }

    override func layout() {
        super.layout()
        let leading = SidebarWorkspaceListMetrics.rowOuterHorizontalPadding
            + SidebarWorkspaceListMetrics.rowContentHorizontalPadding
        let trailing = bounds.width - leading
        let lineHeight = ShellXSidebarHeaderMetrics.brandLineHeight
        let logoSide = ShellXSidebarHeaderMetrics.logoSide

        let brandMidY = lineHeight / 2 + 2
        logoImageView.frame = NSRect(x: leading, y: brandMidY - logoSide / 2, width: logoSide, height: logoSide)
        let nameSize = nameField.intrinsicContentSize
        let nameX = logoImageView.frame.maxX + 8
        nameField.frame = NSRect(
            x: nameX,
            y: brandMidY - ceil(nameSize.height) / 2,
            width: max(0, trailing - nameX),
            height: ceil(nameSize.height)
        )

        let sectionMidY = lineHeight + (bounds.height - lineHeight) / 2
        let buttonSide = ShellXSidebarHeaderMetrics.addButtonSide
        addButton.frame = NSRect(
            x: trailing - buttonSide,
            y: sectionMidY - buttonSide / 2,
            width: buttonSide,
            height: buttonSide
        )
        let sectionSize = sectionField.intrinsicContentSize
        sectionField.frame = NSRect(
            x: leading,
            y: sectionMidY - ceil(sectionSize.height) / 2,
            width: max(0, addButton.frame.minX - 6 - leading),
            height: ceil(sectionSize.height)
        )
    }
}

/// The row under "YOUR MACHINES" while the remote UI is on and signed out:
/// "Sign in to see your other machines". Clicking the row (routed by the
/// table controller to `ShellXRemoteUIActions.handleClick`) opens the
/// sign-in sheet. Fixed height; the label truncates.
@MainActor
final class SidebarSignInRowCellView: NSTableCellView, ShellXSidebarHeaderCell {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarSignInRowCellView")

    private let iconImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseIdentifier
        wantsLayer = true

        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.contentTintColor = ShellXPalette.primaryText.nsColor
        // ShellX: swap for ShellXIcon/ShellXFonts/ShellXLogo after W1 Tasks 7-9 merge
        iconImageView.image = ShellXSidebarIcon.image(
            named: "User_Circle",
            pointSize: ShellXSidebarHeaderMetrics.iconSide
        )
        addSubview(iconImageView)

        let text = String(localized: "remote.signin.row", defaultValue: "Sign in to see your other machines")
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        titleField.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: ShellXPalette.primaryText.nsColor,
                .paragraphStyle: truncating,
            ]
        )
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.isSelectable = false
        titleField.toolTip = text
        addSubview(titleField)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(text)
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

    func configure(header: ShellXSidebarHeaderRow) {
        // Static content.
    }

    override func accessibilityPerformPress() -> Bool {
        ShellXRemoteUIActions.handleClick(on: .signIn)
    }

    override func layout() {
        super.layout()
        let leading = SidebarWorkspaceListMetrics.rowOuterHorizontalPadding
            + SidebarWorkspaceListMetrics.rowContentHorizontalPadding
        let trailing = bounds.width - leading
        let midY = bounds.height / 2
        let iconSide = ShellXSidebarHeaderMetrics.iconSide
        iconImageView.frame = NSRect(x: leading, y: midY - iconSide / 2, width: iconSide, height: iconSide)
        let textX = iconImageView.frame.maxX + 8
        let textHeight = ceil(titleField.attributedStringValue.size().height)
        titleField.frame = NSRect(
            x: textX,
            y: midY - textHeight / 2,
            width: max(0, trailing - textX),
            height: textHeight
        )
    }
}

/// "Add a machine over SSH…": asks for `user@host`, then hands an
/// `ssh://` link to the existing SSH link flow (managed-policy check, trust
/// confirmation, `cmux ssh` launch).
@MainActor
enum ShellXAddMachinePrompt {
    static func present() {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "sidebar.machines.add.ssh.title",
            defaultValue: "Add a Machine over SSH"
        )
        alert.informativeText = String(
            localized: "sidebar.machines.add.ssh.message",
            defaultValue: "Enter the SSH target, for example ubuntu@vm01."
        )
        alert.addButton(withTitle: String(localized: "sidebar.machines.add.ssh.connect", defaultValue: "Connect"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = sshURL(from: field.stringValue),
              AppDelegate.shared?.handleCmuxSSHURLs(from: [url]) == true else {
            NSSound.beep()
            return
        }
    }

    /// `ubuntu@vm01`, `ubuntu@vm01:2222` or `ssh://…` → an `ssh://` URL.
    static func sshURL(from input: String) -> URL? {
        var target = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.lowercased().hasPrefix("ssh://") {
            target = String(target.dropFirst("ssh://".count))
        }
        guard !target.isEmpty, !target.contains(where: \.isWhitespace) else { return nil }
        return URL(string: "ssh://" + target)
    }
}
