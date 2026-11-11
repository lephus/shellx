import AppKit

/// The delegate of ``SignInTextField``'s field: it reports every change, maps Return and Escape to the sheet's actions,
/// and moves the keyboard to the field when asked.
@MainActor
public final class SignInTextFieldCoordinator: NSObject, NSTextFieldDelegate {
    var onChange: @MainActor (String) -> Void
    var onSubmit: @MainActor () -> Void
    var onCancel: @MainActor () -> Void
    /// The `focusRequest` already acted on.
    var focusRequest: Int

    init(
        onChange: @escaping @MainActor (String) -> Void, onSubmit: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void, focusRequest: Int
    ) {
        self.onChange = onChange
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.focusRequest = focusRequest
    }

    /// Reports the field's text on every change, a composition's marked text included, so a composition that ends
    /// without another change still reaches the model.
    ///
    /// - Parameter notification: The field's text-change notification.
    public func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        onChange(field.stringValue)
    }

    /// Return calls `onSubmit` and Escape calls `onCancel`; both are then handled, so Return never reaches another
    /// default button and Escape never opens completion. While the editor has marked text (an input method or a dead
    /// key composing), both stay with the editor and the input method (the app's rule since issue #118).
    ///
    /// - Parameters:
    ///   - control: The field.
    ///   - textView: The field's editor.
    ///   - commandSelector: The command the key maps to.
    /// - Returns: True when the command was handled here.
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onSubmit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel()
            return true
        default:
            return false
        }
    }

    /// Gives `field` the keyboard on the next main-queue turn: SwiftUI may still be placing it in the window, and a
    /// first-responder change inside a view update is not allowed. A field that already has the keyboard keeps its
    /// editing session (and its selection) as it is.
    ///
    /// - Parameter field: The field to focus.
    func takeKeyboard(_ field: RomanInputTextField) {
        Task { @MainActor [weak field] in
            guard let field, let window = field.window else { return }
            if let editor = field.currentEditor(), window.firstResponder === editor { return }
            window.makeFirstResponder(field)
        }
    }
}
