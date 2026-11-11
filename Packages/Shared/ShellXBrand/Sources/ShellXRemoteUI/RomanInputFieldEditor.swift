import AppKit

/// A field editor that sets `inputContext?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]` each
/// time it becomes first responder, so input methods outside the Roman scripts (Apple's Vietnamese Telex and VNI,
/// Japanese, Chinese) are not offered while it edits. It also turns off spelling correction, text replacement and
/// smart quotes and dashes, which would change an address or a code.
///
/// One per ``RomanInputTextField``, so the window's shared field editor and the other fields are untouched. The input
/// context belongs to this text view, so the restriction holds for the whole editing session.
public final class RomanInputFieldEditor: NSTextView {
    /// Always a field editor.
    public override var isFieldEditor: Bool {
        get { true }
        set {}
    }

    /// Applies the Roman-only restriction and the no-correction settings, then becomes first responder.
    ///
    /// The field's cell has set this editor up by now (`NSWindow.makeFirstResponder` hands the editor the keyboard
    /// after `setUpFieldEditorAttributes`), and AppKit activates the input context after the first responder
    /// changes, so the restriction is in place when the input context activates.
    ///
    /// - Returns: Whether the editor accepted first responder status.
    public override func becomeFirstResponder() -> Bool {
        inputContext?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextCompletionEnabled = false
        return super.becomeFirstResponder()
    }
}
