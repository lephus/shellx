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
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.isSelectable = false
        addSubview(nameField)

        sectionField.attributedStringValue = NSAttributedString(
            string: String(localized: "sidebar.machines.title", defaultValue: "YOUR MACHINES"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 0.8,
            ]
        )
        sectionField.lineBreakMode = .byTruncatingTail
        sectionField.isSelectable = false
        addSubview(sectionField)

        let addTitle = String(localized: "sidebar.machines.add.ssh", defaultValue: "Add a machine over SSH…")
        // ShellX: swap for ShellXIcon/ShellXFonts/ShellXLogo after W1 Tasks 7-9 merge
        addButton.glyphImage = ShellXSidebarIcon.image(named: "Add_Plus", pointSize: 12)
        addButton.contentTintColor = .secondaryLabelColor
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
