import AppKit
import Bonsplit
import QuartzCore
import ShellXBrand

/// A thin multicolor border that runs around a tab while its agent waits for the person's answer,
/// a permission or a question (spec 2026-10-29 mobile home focus, §6.7).
///
/// Lay it over the tab's fill, with the fill's frame and corner radius, above the fill and below
/// the content: it draws only a ``lineWidth`` ring inside that rounded shape, so it never covers
/// the tab's text and never changes its size. The ring shows a conic gradient over
/// ``ShellXPalette/waitingBorderStops`` through a rounded-border mask; the gradient layer is a
/// square that covers the tab at every angle and turns once every ``rotationDuration`` seconds,
/// linearly, as a Core Animation animation on the render server. The main thread does no work
/// per frame, and every waiting border turns in phase with the others.
///
/// The ring holds still, in the same colors, under Reduce Motion, while its window cannot be
/// seen, while ``isPresentationActive`` is false, and before it is laid out. While ``isActive``
/// is false the view is hidden and nothing in it animates. It is decorative: it takes no clicks
/// and is not an accessibility element, since the tab's status pill already says the agent needs
/// input.
///
/// ```swift
/// let border = WaitingBorderView()
/// border.cornerRadius = fill.layer?.cornerRadius ?? 0
/// row.addSubview(border, positioned: .below, relativeTo: content)
/// border.frame = fill.frame
/// border.isActive = snapshot.agentNeedsInput
/// ```
@MainActor
final class WaitingBorderView: NSView {
    /// Key of the rotation on ``gradientLayer``.
    static let rotationAnimationKey = "waitingBorder.rotation"

    /// Seconds for one turn of the gradient around the tab.
    static let rotationDuration: CFTimeInterval = 3

    /// Width of the ring, in points.
    static let ringWidth: CGFloat = 1.5

    /// The colors, seen only through the ring; it turns while the border runs.
    let gradientLayer = CAGradientLayer()

    /// Whether the tab's agent waits for the person: the border shows only then.
    ///
    /// Turning it off hides the view and removes its animation.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            isHidden = !isActive
            updateRotation()
        }
    }

    /// Whether the border may move: hosts turn it off for rows that are scrolled away or not presented.
    var isPresentationActive = true {
        didSet {
            guard isPresentationActive != oldValue else { return }
            updateRotation()
        }
    }

    /// Corner radius of the tab's fill, so the ring follows the tab's rounded shape.
    var cornerRadius: CGFloat {
        get { ringMask.cornerRadius }
        set {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ringMask.cornerRadius = newValue
            CATransaction.commit()
        }
    }

    /// Width of the ring as drawn.
    var lineWidth: CGFloat { ringMask.borderWidth }

    /// Holds the gradient and shows it only through ``ringMask``.
    private let ringLayer = CALayer()

    /// The ring: a rounded border, opaque where the gradient shows.
    private let ringMask = CALayer()

    private let environment: any TitleEffectEnvironment

    /// Creates a hidden border; set ``isActive`` to show it.
    ///
    /// - Parameter environment: Where the view learns whether it can be seen and whether motion is
    ///   allowed. The system environment by default; tests pass their own.
    init(environment: any TitleEffectEnvironment = SystemTitleEffectEnvironment()) {
        self.environment = environment
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(false)
        isHidden = true

        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.colors = ShellXPalette.waitingBorderStops.map(\.nsColor.cgColor)
        ringMask.borderWidth = Self.ringWidth
        ringMask.borderColor = CGColor(gray: 0, alpha: 1)
        ringMask.cornerCurve = .continuous
        ringLayer.mask = ringMask
        ringLayer.addSublayer(gradientLayer)
        layer?.addSublayer(ringLayer)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(environmentDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    /// Unavailable: the view is built in code.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - NSView

    /// Fits the ring and the gradient to the new size.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sizeDidChange()
    }

    /// Fits the ring and the gradient to the laid-out size.
    override func layout() {
        super.layout()
        sizeDidChange()
    }

    /// Follows the new window's occlusion and draws the ring at its scale.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(environmentDidChange),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
        }
        updateContentsScale()
        updateRotation()
    }

    /// Draws the ring at the new screen's scale.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    /// Stops the rotation while the view or an ancestor is hidden.
    override func viewDidHide() {
        super.viewDidHide()
        updateRotation()
    }

    /// Starts the rotation again once the view is shown, when it may move.
    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateRotation()
    }

    /// The border is decorative; clicks go to the tab under it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Ring

    private func sizeDidChange() {
        let side = ceil(hypot(bounds.width, bounds.height))
        let square = CGRect(x: 0, y: 0, width: side, height: side)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard ringLayer.frame != bounds || gradientLayer.bounds != square || gradientLayer.position != center else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.frame = bounds
        ringMask.frame = bounds
        gradientLayer.bounds = square
        gradientLayer.position = center
        CATransaction.commit()
        updateRotation()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard gradientLayer.contentsScale != scale else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in [ringLayer, ringMask, gradientLayer] {
            sublayer.contentsScale = scale
        }
        CATransaction.commit()
    }

    @objc private func environmentDidChange() {
        updateRotation()
    }

    // MARK: - Rotation

    /// Whether the gradient may turn now.
    private var mayRotate: Bool {
        guard isActive, isPresentationActive, window != nil, !bounds.isEmpty else { return false }
        guard environment.isVisible(self) else { return false }
        return !environment.reducesMotion
    }

    /// Starts the rotation when the gradient may turn, and removes it as soon as it may not.
    private func updateRotation() {
        guard mayRotate else {
            gradientLayer.removeAnimation(forKey: Self.rotationAnimationKey)
            return
        }
        guard gradientLayer.animation(forKey: Self.rotationAnimationKey) == nil else { return }
        gradientLayer.add(makeRotation(), forKey: Self.rotationAnimationKey)
    }

    /// One endless, linear turn every ``rotationDuration`` seconds.
    ///
    /// It starts at the shared media clock's phase, so borders that start at different times turn
    /// together and a border that starts again does not jump. A smooth gradient needs no more than
    /// 30 frames a second; asking for that keeps WindowServer from recompositing the row at the
    /// display's full refresh rate.
    private func makeRotation() -> CAAnimation {
        let globalNow = CACurrentMediaTime()
        let phase = globalNow.truncatingRemainder(dividingBy: Self.rotationDuration)
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -2 * CGFloat.pi
        rotation.duration = Self.rotationDuration
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        rotation.isRemovedOnCompletion = false
        rotation.beginTime = gradientLayer.convertTime(globalNow, from: nil) - phase
        rotation.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 60, preferred: 30)
        return rotation
    }
}
