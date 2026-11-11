import AppKit

/// The field behind ``SignInTextField``; its cell hands out the field's own ``RomanInputFieldEditor``, so only this
/// field edits with Roman input sources.
public final class RomanInputTextField: NSTextField {
    /// The cell that supplies the field's own editor (the precedent is CmuxBrowser's `BrowserOmnibarPasteTextFieldCell`).
    private final class Cell: NSTextFieldCell {
        private lazy var editor = RomanInputFieldEditor()

        override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
    }

    /// Makes every instance use the cell that supplies ``RomanInputFieldEditor``.
    public override class var cellClass: AnyClass? {
        get { Cell.self }
        set { super.cellClass = newValue }
    }

    /// Runs once, the first time the field moves into a window (``SignInTextField`` takes the keyboard then).
    var onFirstMoveToWindow: (@MainActor (RomanInputTextField) -> Void)?
    private var hasMovedToWindow = false

    /// Reports the first move into a window to ``onFirstMoveToWindow``.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasMovedToWindow else { return }
        hasMovedToWindow = true
        onFirstMoveToWindow?(self)
    }
}
