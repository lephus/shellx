import AppKit

/// The field behind ``SignInTextField``; its cell hands out the field's own ``PlainLayoutFieldEditor``, so only this
/// field edits with the person's plain keyboard layouts.
public final class PlainLayoutTextField: NSTextField {
    /// The cell that supplies the field's own editor (the precedent is CmuxBrowser's `BrowserOmnibarPasteTextFieldCell`).
    private final class Cell: NSTextFieldCell {
        private lazy var editor = PlainLayoutFieldEditor()

        override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
    }

    /// Makes every instance use the cell that supplies ``PlainLayoutFieldEditor``.
    public override class var cellClass: AnyClass? {
        get { Cell.self }
        set { super.cellClass = newValue }
    }

    /// Runs once, the first time the field moves into a window (``SignInTextField`` takes the keyboard then).
    var onFirstMoveToWindow: (@MainActor (PlainLayoutTextField) -> Void)?
    private var hasMovedToWindow = false

    /// Whether the sheet lets the field take input (``SignInTextField``'s `isEnabled`). The field is enabled only when
    /// this and the last value given to ``isEnabled`` both allow it.
    var takesInput = true {
        didSet {
            guard takesInput != oldValue else { return }
            super.isEnabled = requestedEnabled && takesInput
        }
    }
    private var requestedEnabled = true

    /// SwiftUI sets this from its environment after `updateNSView`, and again whenever it applies the environment
    /// (a window that changes its appearance, say), which would turn a field the sheet keeps off back on. The field
    /// stays off while ``takesInput`` is false.
    public override var isEnabled: Bool {
        get { super.isEnabled }
        set {
            requestedEnabled = newValue
            super.isEnabled = newValue && takesInput
        }
    }

    /// Reports the first move into a window to ``onFirstMoveToWindow``.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasMovedToWindow else { return }
        hasMovedToWindow = true
        onFirstMoveToWindow?(self)
    }
}
