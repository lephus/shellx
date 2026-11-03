import AppKit
import Bonsplit
import QuartzCore
import ShellXBrand

/// The "✦ Automations" button in the sidebar's brand header: a row-colored pill with a thin
/// multicolor ring that turns slowly around it, a twinkling ✦, and a trailing count.
///
/// Every animation runs on Core Animation layers only: the ring is a conic
/// ``CAGradientLayer`` seen through a 1 pt ``CAShapeLayer`` stroke and turned by a
/// `transform.rotation.z` animation; the ✦ twinkles on its own layer. Nothing redraws per
/// frame, so the sidebar table never re-renders for it. Under Reduce Motion, while the window
/// cannot be seen, and before layout, the ring holds still and the ✦ does not twinkle.
///
/// It is a button (an `NSButton` with no bezel) so the sidebar table hands it its clicks; every
/// point inside it hits the button itself, never its labels.
@MainActor
final class ShellXAutomationsSidebarButton: NSButton {
    /// Key of the rotation on ``gradientLayer``.
    static let ringAnimationKey = "automations.ring"
    /// Key of the ✦ twinkle on ``sparkleLayer``.
    static let twinkleAnimationKey = "automations.twinkle"
    /// Seconds for one turn of the ring.
    static let ringDuration: CFTimeInterval = 4
    /// Seconds for one twinkle of the ✦.
    static let twinkleDuration: CFTimeInterval = 2.4
    /// Ring colors: blue, violet, pink, amber, green (and back to blue for a seamless turn).
    static let ringHexes: [UInt32] = [0x60a5fa, 0xa78bfa, 0xf472b6, 0xfbbf24, 0x34d399]
    static let height: CGFloat = 28
    static let cornerRadius: CGFloat = 9
    static let ringWidth: CGFloat = 1

    /// Automations and skills; the count pill hides at 0.
    var count: Int = 0 {
        didSet {
            guard count != oldValue else { return }
            updateCount()
        }
    }

    /// Runs the user has not seen; a small dot shows while it is above 0.
    var unreadCount: Int = 0 {
        didSet {
            guard unreadCount != oldValue else { return }
            unreadDot.isHidden = unreadCount <= 0
            needsLayout = true
        }
    }

    /// Whether motion is reduced. Starts from the system setting and follows it; tests set it.
    var reduceMotion: Bool {
        didSet {
            guard reduceMotion != oldValue else { return }
            updateAnimations()
        }
    }

    /// Called on click and on the accessibility press.
    var onClick: (() -> Void)?

    /// Whether the ring is turning now.
    var isRingAnimating: Bool { gradientLayer.animation(forKey: Self.ringAnimationKey) != nil }

    /// Whether the ✦ is twinkling now.
    var isTwinkling: Bool { sparkleLayer.animation(forKey: Self.twinkleAnimationKey) != nil }

    /// Whether the count pill shows.
    var isCountVisible: Bool { !countField.isHidden }

    /// The colors, seen only through the ring.
    let gradientLayer = CAGradientLayer()
    /// The ✦ glyph, on its own layer so it can twinkle.
    let sparkleLayer = CATextLayer()

    private let fillLayer = CALayer()
    private let ringLayer = CALayer()
    private let ringMask = CAShapeLayer()
    private let titleField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private let unreadDot = NSView()
    private let environment: any TitleEffectEnvironment
    private let isApplicationActive: @MainActor () -> Bool

    /// - Parameters:
    ///   - environment: Where the button learns whether it can be seen and whether
    ///     motion is reduced. The system environment by default; tests pass their own.
    ///   - notificationCenter: Where the app's did-become-active and did-resign-active notifications arrive.
    ///   - isApplicationActive: Whether ShellX is the active app; the ring and the ✦ rest while it is not.
    init(
        environment: any TitleEffectEnvironment = SystemTitleEffectEnvironment(),
        notificationCenter: NotificationCenter = .default,
        isApplicationActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive }
    ) {
        self.environment = environment
        self.isApplicationActive = isApplicationActive
        reduceMotion = environment.reducesMotion
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        setButtonType(.momentaryChange)
        focusRingType = .none
        target = self
        action = #selector(didClick)
        wantsLayer = true
        layer?.masksToBounds = false

        fillLayer.cornerRadius = Self.cornerRadius
        fillLayer.cornerCurve = .continuous
        layer?.addSublayer(fillLayer)

        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        let colors = (Self.ringHexes + [Self.ringHexes[0]]).map { ShellXColor(hex: $0).nsColor.cgColor }
        gradientLayer.colors = colors
        ringMask.fillColor = nil
        ringMask.strokeColor = CGColor(gray: 0, alpha: 1)
        ringMask.lineWidth = Self.ringWidth
        ringLayer.mask = ringMask
        ringLayer.addSublayer(gradientLayer)
        layer?.addSublayer(ringLayer)

        sparkleLayer.string = "✦"
        sparkleLayer.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        sparkleLayer.fontSize = 12
        sparkleLayer.alignmentMode = .center
        sparkleLayer.foregroundColor = ShellXPalette.primary.nsColor.cgColor
        layer?.addSublayer(sparkleLayer)

        let label = String(localized: "sidebar.automations.button", defaultValue: "Automations")
        titleField.stringValue = label
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleField.textColor = ShellXSidebarText.title
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.isSelectable = false
        addSubview(titleField)

        countField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        countField.textColor = ShellXSidebarText.muted
        countField.alignment = .center
        countField.isSelectable = false
        countField.wantsLayer = true
        countField.layer?.cornerRadius = 7
        countField.isHidden = true
        addSubview(countField)

        unreadDot.wantsLayer = true
        unreadDot.layer?.cornerRadius = 3
        unreadDot.layer?.backgroundColor = ShellXPalette.primary.nsColor.cgColor
        unreadDot.isHidden = true
        addSubview(unreadDot)

        toolTip = String(
            localized: "sidebar.automations.tooltip",
            defaultValue: "Create and manage skills, workflows and cronjobs"
        )
        setAccessibilityLabel(accessibilityText())
        applyColors()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            notificationCenter.addObserver(self, selector: #selector(applicationActivityDidChange), name: name, object: nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - NSView

    override var isFlipped: Bool { true }

    /// Every point inside the button is the button, so the table hands it the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func layout() {
        super.layout()
        let inset = SidebarWorkspaceListMetrics.rowContentHorizontalPadding
        let midY = bounds.height / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = bounds
        ringLayer.frame = bounds
        ringMask.frame = bounds
        let half = Self.ringWidth / 2
        ringMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: half, dy: half),
            cornerWidth: Self.cornerRadius - half,
            cornerHeight: Self.cornerRadius - half,
            transform: nil
        )
        let side = ceil(hypot(bounds.width, bounds.height))
        gradientLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradientLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        sparkleLayer.frame = CGRect(x: inset - 2, y: midY - 8, width: 16, height: 16)
        CATransaction.commit()

        var trailing = bounds.width - inset
        if !countField.isHidden {
            let textWidth = ceil(countField.intrinsicContentSize.width)
            let pillWidth = max(18, textWidth + 10)
            countField.frame = NSRect(x: trailing - pillWidth, y: midY - 7, width: pillWidth, height: 14)
            trailing = countField.frame.minX - 6
        }
        if !unreadDot.isHidden {
            unreadDot.frame = NSRect(x: trailing - 6, y: midY - 3, width: 6, height: 6)
            trailing = unreadDot.frame.minX - 6
        }
        let titleX = sparkleLayer.frame.maxX + 4
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        titleField.frame = NSRect(x: titleX, y: midY - titleHeight / 2, width: max(0, trailing - titleX), height: titleHeight)
        updateAnimations()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(visibilityDidChange),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
        }
        updateContentsScale()
        updateAnimations()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateAnimations()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimations()
    }

    // MARK: - Content

    @objc private func didClick() {
        onClick?()
    }

    private func updateCount() {
        countField.stringValue = "\(count)"
        countField.isHidden = count <= 0
        setAccessibilityLabel(accessibilityText())
        needsLayout = true
    }

    private func accessibilityText() -> String {
        let format = String(localized: "sidebar.automations.accessibility", defaultValue: "Automations, \(count)")
        return format
    }

    /// Resolves the fill and pill colors for the current appearance.
    private func applyColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.backgroundColor = isDark
            ? ShellXPalette.rowHover.nsColor.cgColor
            : NSColor.black.withAlphaComponent(0.05).cgColor
        countField.layer?.backgroundColor = isDark
            ? ShellXPalette.raise.nsColor.cgColor
            : NSColor.black.withAlphaComponent(0.07).cgColor
        CATransaction.commit()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in [fillLayer, ringLayer, ringMask, gradientLayer, sparkleLayer] {
            sublayer.contentsScale = scale
        }
        CATransaction.commit()
    }

    // MARK: - Motion

    @objc private func accessibilityDisplayOptionsDidChange() {
        reduceMotion = environment.reducesMotion
        updateAnimations()
    }

    @objc private func visibilityDidChange() {
        updateAnimations()
    }

    @objc private func applicationActivityDidChange() {
        updateAnimations()
    }

    /// Whether the ring and the ✦ may move now: only while ShellX is active and the button can be seen.
    private var mayAnimate: Bool {
        guard !reduceMotion, isApplicationActive(), window != nil, !bounds.isEmpty else { return false }
        return environment.isVisible(self)
    }

    /// Starts both animations when they may run and removes them as soon as they may not.
    private func updateAnimations() {
        guard mayAnimate else {
            gradientLayer.removeAnimation(forKey: Self.ringAnimationKey)
            sparkleLayer.removeAnimation(forKey: Self.twinkleAnimationKey)
            return
        }
        if gradientLayer.animation(forKey: Self.ringAnimationKey) == nil {
            gradientLayer.add(makeRotation(), forKey: Self.ringAnimationKey)
        }
        if sparkleLayer.animation(forKey: Self.twinkleAnimationKey) == nil {
            sparkleLayer.add(makeTwinkle(), forKey: Self.twinkleAnimationKey)
        }
    }

    /// One endless, linear turn every ``ringDuration`` seconds, at 30 frames a second.
    private func makeRotation() -> CAAnimation {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -2 * CGFloat.pi
        rotation.duration = Self.ringDuration
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        rotation.isRemovedOnCompletion = false
        rotation.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 60, preferred: 30)
        return rotation
    }

    /// A gentle grow-and-dim of the ✦ every ``twinkleDuration`` seconds.
    private func makeTwinkle() -> CAAnimation {
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 0.78, 1]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 0.5, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = Self.twinkleDuration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.isRemovedOnCompletion = false
        return group
    }
}
