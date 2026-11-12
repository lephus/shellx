import AppKit

/// A field editor that, each time it becomes first responder, allows only the languages of the person's own plain
/// keyboard layouts (``PlainLayoutLocales``) in its input context. With ABC and Vietnamese Simple Telex enabled it
/// allows `en`, so Telex is not offered while it edits; with no plain layout it sets no restriction. It also turns off
/// spelling correction, text replacement and smart quotes and dashes, which would change an address or a code, and it
/// keeps undo, telling the field about each undo and redo.
///
/// One per ``PlainLayoutTextField``, so the window's shared field editor and the other fields are untouched. The input
/// context belongs to this text view, so the restriction holds for the whole editing session.
public final class PlainLayoutFieldEditor: NSTextView {
    private var undoObservers: [any NSObjectProtocol] = []

    /// Always a field editor.
    public override var isFieldEditor: Bool {
        get { true }
        set {}
    }

    /// Applies the language restriction and the no-correction settings, becomes first responder, then listens for
    /// undo and redo.
    ///
    /// The field's cell has set this editor up by now (`NSWindow.makeFirstResponder` hands the editor the keyboard
    /// after the cell's setup), and AppKit activates the input context after the first responder changes, so the
    /// restriction is in place when the input context activates. The enabled input sources are read again on every
    /// focus, so a layout the person adds while the app runs counts.
    ///
    /// - Returns: Whether the editor accepted first responder status.
    public override func becomeFirstResponder() -> Bool {
        inputContext?.allowedInputSourceLocales = PlainLayoutLocales(sources: SystemKeyboardInputSources().enabled()).locales
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextCompletionEnabled = false
        allowsUndo = true
        let accepted = super.becomeFirstResponder()
        if accepted { observeUndo() }
        return accepted
    }

    /// Stops listening for undo and redo once the editor gives the keyboard up.
    ///
    /// - Returns: Whether the editor resigned first responder status.
    public override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { stopObservingUndo() }
        return resigned
    }

    /// AppKit's undo and redo change the text without `didChangeText()`, so the field's delegate would never hear of
    /// the change and the model would keep the old text. Each undo and redo of this editing session calls it.
    private func observeUndo() {
        stopObservingUndo()
        guard let undoManager else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            undoObservers.append(center.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didChangeText() }
            })
        }
    }

    private func stopObservingUndo() {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        undoObservers.removeAll()
    }
}
