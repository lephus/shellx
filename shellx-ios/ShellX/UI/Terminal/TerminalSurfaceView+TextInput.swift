import ShellXAppCore
import ShellXLinkCore
import UIKit

/// The surface as the keyboard's text input. Its document is only the marked text (an input method's word in progress,
/// Telex or VNI), which stays on the phone; committed text, Return, Backspace with nothing composed, the key bar's keys
/// and hardware keys go to the model, which sends them (S2 §3.6, §3.7).
extension TerminalSurfaceView: UITextInput {
    // MARK: - UIKeyInput

    /// Always true, so Backspace reaches `deleteBackward` with nothing composed.
    var hasText: Bool { true }

    func insertText(_ text: String) {
        model.insertText(text)
        markedSelection = 0
        inputHappened(keyboardMarked: "")
    }

    func deleteBackward() {
        let composing = !model.typing.markedText.isEmpty
        model.deleteBackward()
        if composing { markedSelection = min(markedSelection, markedLength) }
        inputHappened(keyboardMarked: composing ? model.typing.markedText : "")
    }

    // MARK: - Marked text

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        let text = markedText ?? ""
        model.setMarkedText(text)
        markedSelection = min(max(selectedRange.location + selectedRange.length, 0), markedLength)
        inputHappened(keyboardMarked: text)
    }

    func unmarkText() {
        model.unmarkText()
        markedSelection = 0
        inputHappened(keyboardMarked: "")
    }

    var markedTextRange: UITextRange? {
        markedLength == 0 ? nil : TerminalTextRange(0, markedLength)
    }

    var markedTextStyle: [NSAttributedString.Key: Any]? {
        get { nil }
        set {}
    }

    var selectedTextRange: UITextRange? {
        get {
            let caret = min(markedSelection, markedLength)
            return TerminalTextRange(caret, caret)
        }
        set {
            if let range = newValue as? TerminalTextRange { markedSelection = min(max(range.endOffset, 0), markedLength) }
        }
    }

    func text(in range: UITextRange) -> String? {
        guard let range = clamped(range) else { return nil }
        return (model.typing.markedText as NSString).substring(with: range)
    }

    /// Commits the marked text with `range` replaced.
    func replace(_ range: UITextRange, withText text: String) {
        let marked = model.typing.markedText as NSString
        let replaced = clamped(range).map { marked.replacingCharacters(in: $0, with: text) } ?? (marked as String) + text
        insertText(replaced)
    }

    // MARK: - Positions

    var beginningOfDocument: UITextPosition { TerminalTextPosition(0) }
    var endOfDocument: UITextPosition { TerminalTextPosition(markedLength) }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let from = fromPosition as? TerminalTextPosition, let to = toPosition as? TerminalTextPosition else { return nil }
        return TerminalTextRange(min(from.offset, to.offset), max(from.offset, to.offset))
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let position = position as? TerminalTextPosition else { return nil }
        let moved = position.offset + offset
        return (0...markedLength).contains(moved) ? TerminalTextPosition(moved) : nil
    }

    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        switch direction {
        case .left, .up: self.position(from: position, offset: -offset)
        default: self.position(from: position, offset: offset)
        }
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        let a = (position as? TerminalTextPosition)?.offset ?? 0
        let b = (other as? TerminalTextPosition)?.offset ?? 0
        return a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        ((toPosition as? TerminalTextPosition)?.offset ?? 0) - ((from as? TerminalTextPosition)?.offset ?? 0)
    }

    var tokenizer: UITextInputTokenizer { inputTokenizer }

    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        switch direction {
        case .left, .up: range.start
        default: range.end
        }
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let position = position as? TerminalTextPosition else { return nil }
        switch direction {
        case .left, .up: return TerminalTextRange(0, position.offset)
        default: return TerminalTextRange(position.offset, markedLength)
        }
    }

    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .leftToRight
    }

    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    // MARK: - Geometry (the keyboard's candidate bar and caret sit at the terminal's cursor)

    func firstRect(for range: UITextRange) -> CGRect {
        canvas.convert(canvas.cursorRect(), to: self)
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        let cell = canvas.convert(canvas.cursorRect(), to: self)
        return CGRect(x: cell.minX, y: cell.minY, width: 2, height: cell.height)
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

    func closestPosition(to point: CGPoint) -> UITextPosition? { endOfDocument }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? { range.end }

    func characterRange(at point: CGPoint) -> UITextRange? { TerminalTextRange(markedLength, markedLength) }

    // MARK: - Traits: a terminal takes what is typed as it is

    var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
    var autocapitalizationType: UITextAutocapitalizationType { get { .none } set {} }
    var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
    var smartQuotesType: UITextSmartQuotesType { get { .no } set {} }
    var smartDashesType: UITextSmartDashesType { get { .no } set {} }
    var smartInsertDeleteType: UITextSmartInsertDeleteType { get { .no } set {} }
    var inlinePredictionType: UITextInlinePredictionType { get { .no } set {} }
    /// The default keyboard, so the Vietnamese (Telex, VNI) and other input methods stay available.
    var keyboardType: UIKeyboardType { get { .default } set {} }
    var returnKeyType: UIReturnKeyType { get { .default } set {} }
    var keyboardAppearance: UIKeyboardAppearance { get { .default } set {} }
    @available(iOS 18.0, *)
    var writingToolsBehavior: UIWritingToolsBehavior { get { .none } set {} }

    // MARK: - Helpers

    private var markedLength: Int { (model.typing.markedText as NSString).length }

    private func clamped(_ range: UITextRange) -> NSRange? {
        guard let range = range as? TerminalTextRange else { return nil }
        let start = min(max(range.startOffset, 0), markedLength)
        let end = min(max(range.endOffset, start), markedLength)
        return NSRange(location: start, length: end - start)
    }
}

/// A UTF-16 offset in the marked text.
private final class TerminalTextPosition: UITextPosition {
    let offset: Int
    init(_ offset: Int) { self.offset = offset }
}

private final class TerminalTextRange: UITextRange {
    private let lower: TerminalTextPosition
    private let upper: TerminalTextPosition
    init(_ start: Int, _ end: Int) {
        lower = TerminalTextPosition(start)
        upper = TerminalTextPosition(end)
    }
    var startOffset: Int { lower.offset }
    var endOffset: Int { upper.offset }
    override var start: UITextPosition { lower }
    override var end: UITextPosition { upper }
    override var isEmpty: Bool { lower.offset >= upper.offset }
}
