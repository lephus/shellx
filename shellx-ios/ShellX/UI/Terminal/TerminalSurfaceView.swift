import ShellXAppCore
import ShellXLinkCore
import UIKit

/// The scroll physics around the canvas: content = history and screen rows on the main screen, screen rows on the
/// alternate one, at `TerminalZoom.scale(fit:)`; follows the bottom unless scrolled up (then holds by `topShift`); pinch
/// zoom; alternate-screen pans become `model.scroll(lines:)`; reports `TerminalGeometry.phoneGrid` to the model.
final class TerminalSurfaceView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let model: TerminalViewModel
    let font: TerminalFont
    let canvas: TerminalCanvasView

    /// Called with true / false when the view becomes / stops being the first responder (Task 9).
    var onFocusChange: (Bool) -> Void = { _ in }
    /// The tab's name as its chip shows it, for VoiceOver.
    var title = ""
    private(set) var isFollowingBottom = true

    private var zoom = TerminalZoom()
    private var scale: CGFloat = 1
    private var reportedSize: CGSize = .zero
    private var lastSnapshots: Int?
    private var lastTopShift = 0
    private var lastSentInputs = 0
    private var lastTyping = TerminalTyping()
    private var pinchStartScale: CGFloat = 1
    /// The grid point under the fingers when the pinch began, and where on the view it was.
    private var pinchAnchor: (grid: CGPoint, view: CGPoint)?
    private var panCarry: CGFloat = 0
    private var panTranslation: CGFloat = 0
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
    private lazy var alternatePan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
    /// The delegate of the pinch and the alternate-screen pan. Not `self`: the scroll view is already its own pan's
    /// delegate, and answering for that pan would change how UIKit scrolls.
    private lazy var simultaneous = SimultaneousGestures { [unowned self] in self.panGestureRecognizer }

    // MARK: Text input (the extension in TerminalSurfaceView+TextInput.swift)

    /// Where Paste reads from: `.general`; tests set a named one.
    var pasteboard: UIPasteboard = .general
    weak var inputDelegate: UITextInputDelegate?
    /// The caret in the marked text (a UTF-16 offset), as the keyboard last placed it.
    var markedSelection = 0
    /// The marked text as the keyboard believes it is; when the model's differs, the keyboard is told to start again.
    private var keyboardMarked = ""
    private var keyboardResetPending = false
    /// Hardware presses sent as named keys, kept from UIKit's text system until they end.
    private var sentPresses: Set<ObjectIdentifier> = []
    private(set) lazy var inputTokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    private lazy var longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
    private lazy var editMenu = UIEditMenuInteraction(delegate: nil)

    init(model: TerminalViewModel, font: TerminalFont = .standard) {
        self.model = model
        self.font = font
        canvas = TerminalCanvasView(model: model, font: font)
        super.init(frame: .zero)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        isDirectionalLockEnabled = true
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = true
        indicatorStyle = .white
        backgroundColor = .clear
        addSubview(canvas)
        pinch.delegate = simultaneous
        addGestureRecognizer(pinch)
        alternatePan.delegate = simultaneous
        alternatePan.maximumNumberOfTouches = 1
        addGestureRecognizer(alternatePan)
        addGestureRecognizer(tap)
        longPress.minimumPressDuration = 0.5
        addGestureRecognizer(longPress)
        addInteraction(editMenu)
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
        accessibilityIdentifier = "terminal.surface"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Updates

    func update(revision: Int, snapshots: Int, topShift: Int, phase: TerminalViewPhase, typing: TerminalTyping, sentInputs: Int) {
        let screen = model.screen
        backgroundColor = screen.palette.map { UIColor(cgColor: TerminalCanvasView.color(TerminalColors.background($0))) } ?? .clear
        alwaysBounceVertical = !screen.alt
        canvas.showsCursor = phase == .live
        let newSnapshot = snapshots != lastSnapshots
        let typed = sentInputs != lastSentInputs
        let shift = topShift - lastTopShift
        lastSnapshots = snapshots
        lastSentInputs = sentInputs
        lastTopShift = topShift
        if typing != lastTyping {
            lastTyping = typing
            typingChanged()
        }
        layoutContent()
        if newSnapshot || typed || isFollowingBottom {
            isFollowingBottom = true
            scrollToBottom()
        } else if shift != 0 {
            var offset = contentOffset
            offset.y = clamp(offset.y + CGFloat(shift) * font.cell.height * scale, max: maxOffset.y)
            contentOffset = offset
        }
        canvas.setNeedsDisplay()
    }

    /// The marked text or the ctrl latch changed: redraw, and reset the keyboard when the marked text changed without
    /// it (a key bar or hardware key committed the word).
    func typingChanged() {
        canvas.setNeedsDisplay()
        syncKeyboard()
    }

    // MARK: - Keyboard

    /// After a call from the keyboard: `keyboardMarked` is what it now believes is composed.
    func inputHappened(keyboardMarked marked: String) {
        keyboardMarked = marked
        canvas.setNeedsDisplay()
        syncKeyboard()
    }

    /// When the model's marked text differs from the keyboard's (a key committed it, ctrl took the first composed
    /// letter), tell the keyboard on the next main-queue turn, so it drops its composition.
    private func syncKeyboard() {
        guard model.typing.markedText != keyboardMarked else { return }
        keyboardMarked = model.typing.markedText
        markedSelection = min(markedSelection, (keyboardMarked as NSString).length)
        guard !keyboardResetPending else { return }
        keyboardResetPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            keyboardResetPending = false
            inputDelegate?.selectionWillChange(self)
            inputDelegate?.textWillChange(self)
            inputDelegate?.textDidChange(self)
            inputDelegate?.selectionDidChange(self)
        }
    }

    // MARK: - Focus

    override var canBecomeFirstResponder: Bool {
        model.phase == .live || model.phase == .connecting
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { tellFocus(true) }
        return became
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let wasFirst = isFirstResponder
        let resigned = super.resignFirstResponder()
        if resigned && wasFirst { tellFocus(false) }
        return resigned
    }

    private func tellFocus(_ focused: Bool) {
        Task { @MainActor [weak self] in self?.onFocusChange(focused) }
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended { becomeFirstResponder() }
    }

    /// A long press opens the edit menu at the touch: Paste, when the pasteboard holds text.
    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        becomeFirstResponder()
        let point = recognizer.location(in: self)
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }

    // MARK: - Paste

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(UIResponderStandardEditActions.paste(_:)) && pasteboard.hasStrings
    }

    override func paste(_ sender: Any?) {
        guard let text = pasteboard.string else { return }
        model.paste(text)
        canvas.setNeedsDisplay()
    }

    // MARK: - Hardware keys

    /// Esc, tab, arrows, home, end, page up and down, forward delete and ctrl+letter go out as named keys; the rest
    /// (letters, Return, Backspace, ⌘ shortcuts, anything while composing) go on to UIKit's text system.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var rest = Set<UIPress>()
        for press in presses {
            guard let key = press.key,
                  case let .send(name, mods) = TerminalHardwareKeys.action(
                      usage: key.keyCode.rawValue, modifiers: Self.modifiers(key.modifierFlags),
                      composing: !model.typing.markedText.isEmpty)
            else {
                rest.insert(press)
                continue
            }
            sentPresses.insert(ObjectIdentifier(press))
            model.press(name, mods: mods)
        }
        if rest.count != presses.count {
            canvas.setNeedsDisplay()
            syncKeyboard()
        }
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { !sentPresses.contains(ObjectIdentifier($0)) }
        if !rest.isEmpty { super.pressesChanged(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = finish(presses)
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = finish(presses)
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }

    /// The presses UIKit saw begin; the ones sent as named keys are forgotten.
    private func finish(_ presses: Set<UIPress>) -> Set<UIPress> {
        presses.filter { sentPresses.remove(ObjectIdentifier($0)) == nil }
    }

    private static func modifiers(_ flags: UIKeyModifierFlags) -> TerminalHardwareModifiers {
        var modifiers: TerminalHardwareModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.alternate) { modifiers.insert(.alternate) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutContent()
        if isFollowingBottom && !isTracking && !isDecelerating && pinchAnchor == nil { scrollToBottom() }
        canvas.frame = bounds
        canvas.origin = bounds.origin
        if bounds.size != reportedSize, bounds.width > 0, bounds.height > 0 {
            reportedSize = bounds.size
            let grid = TerminalGeometry.phoneGrid(viewport: bounds.size, cell: font.cell)
            // Never inside the layout pass: the model's change re-renders SwiftUI.
            Task { @MainActor [weak self] in self?.model.setPhoneGrid(cols: grid.cols, rows: grid.rows) }
        }
    }

    /// The content size at the current scale: fit to the width unless pinched (a grid of another width goes back to fit).
    private func layoutContent() {
        let screen = model.screen
        zoom.gridChanged(cols: screen.cols)
        let fit = TerminalGeometry.fitScale(cols: screen.cols, cell: font.cell, viewportWidth: bounds.width)
        scale = zoom.scale(fit: fit)
        canvas.scale = scale
        let padding = TerminalGeometry.padding
        let shownRows = (screen.alt ? 0 : screen.historyRows.count) + screen.rows
        let size = CGSize(
            width: 2 * padding + CGFloat(screen.cols) * font.cell.width * scale,
            height: 2 * padding + CGFloat(shownRows) * font.cell.height * scale)
        if contentSize != size { contentSize = size }
    }

    private var maxOffset: CGPoint {
        CGPoint(x: max(0, contentSize.width - bounds.width), y: max(0, contentSize.height - bounds.height))
    }

    private func clamp(_ value: CGFloat, max upper: CGFloat) -> CGFloat { min(max(value, 0), upper) }

    private func scrollToBottom() {
        let target = CGPoint(x: clamp(contentOffset.x, max: maxOffset.x), y: maxOffset.y)
        if contentOffset != target { contentOffset = target }
    }

    // MARK: - Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isTracking || isDragging || isDecelerating {
            isFollowingBottom = contentOffset.y >= maxOffset.y - font.cell.height * scale / 2
        }
    }

    // MARK: - Pinch

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        let padding = TerminalGeometry.padding
        switch recognizer.state {
        case .began:
            pinchStartScale = scale
            let point = recognizer.location(in: self)
            let grid = CGPoint(x: (point.x - padding) / scale, y: (point.y - padding) / scale)
            pinchAnchor = (grid, CGPoint(x: point.x - contentOffset.x, y: point.y - contentOffset.y))
        case .changed:
            guard let anchor = pinchAnchor else { return }
            let fit = TerminalGeometry.fitScale(cols: model.screen.cols, cell: font.cell, viewportWidth: bounds.width)
            zoom.pinch(to: pinchStartScale * recognizer.scale, fit: fit)
            layoutContent()
            // Keep the content point under the fingers in place.
            let offset = CGPoint(
                x: clamp(padding + anchor.grid.x * scale - anchor.view.x, max: maxOffset.x),
                y: clamp(padding + anchor.grid.y * scale - anchor.view.y, max: maxOffset.y))
            contentOffset = offset
            canvas.setNeedsDisplay()
        default:
            pinchAnchor = nil
            isFollowingBottom = contentOffset.y >= maxOffset.y - font.cell.height * scale / 2
        }
    }

    // MARK: - Alternate-screen scrolling

    /// Only on the alternate screen when its content fits vertically, and only for a mostly vertical pan, so a sideways
    /// swipe still turns the page.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === alternatePan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard model.screen.alt, contentSize.height <= bounds.height + 0.5 else { return false }
        let velocity = alternatePan.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x)
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            panCarry = 0
            panTranslation = 0
        case .changed:
            let translation = recognizer.translation(in: self).y
            let step = TerminalGeometry.scrollLines(
                translation: translation - panTranslation, carry: panCarry, lineHeight: font.cell.height, scale: scale)
            panTranslation = translation
            panCarry = step.carry
            if step.lines != 0 { model.scroll(lines: step.lines) }
        default:
            panCarry = 0
            panTranslation = 0
        }
    }

    // MARK: - Accessibility

    override var accessibilityLabel: String? {
        get { String(localized: "terminal.surface.label \(title)") }
        set {}
    }

    override var accessibilityValue: String? {
        get { model.screen.screenText().joined(separator: "\n") }
        set {}
    }
}

/// Lets a gesture recognizer run together with the scroll view's own pan.
private final class SimultaneousGestures: NSObject, UIGestureRecognizerDelegate {
    private let scrollPan: () -> UIGestureRecognizer

    init(scrollPan: @escaping () -> UIGestureRecognizer) {
        self.scrollPan = scrollPan
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        other === scrollPan()
    }
}
